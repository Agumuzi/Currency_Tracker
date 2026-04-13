//
//  KeychainStore.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

enum EnhancedCredentialKind: String, CaseIterable, Identifiable, Sendable {
    case twelveData
    case openExchangeRates

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .twelveData:
            "Twelve Data"
        case .openExchangeRates:
            "Open Exchange Rates"
        }
    }

    var title: String {
        switch self {
        case .twelveData:
            "Twelve Data API Key"
        case .openExchangeRates:
            "Open Exchange Rates App ID"
        }
    }

    var placeholder: String {
        "留空则不启用"
    }

    fileprivate var account: String {
        switch self {
        case .twelveData:
            "enhanced-source.twelve-data.api-key"
        case .openExchangeRates:
            "enhanced-source.open-exchange-rates.app-id"
        }
    }

    fileprivate var legacyDefaultsKey: String {
        switch self {
        case .twelveData:
            "twelveDataAPIKey"
        case .openExchangeRates:
            "openExchangeRatesAppID"
        }
    }
}

protocol SecretStoring {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String) throws
}

struct LocalSecretStore: SecretStoring {
    enum Error: Swift.Error {
        case invalidEncoding
    }

    let service: String
    private let fileURL: URL

    init(service: String) {
        self.service = service

        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("CurrencyTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let normalizedService = service
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let fileName = normalizedService.isEmpty ? "local-secrets.json" : "local-secrets-\(normalizedService).json"
        fileURL = directoryURL.appendingPathComponent(fileName)
    }

    func read(account: String) throws -> String? {
        try loadValues()[account]
    }

    func write(_ value: String, account: String) throws {
        var values = try loadValues()
        values[account] = value
        try saveValues(values)
    }

    func delete(account: String) throws {
        var values = try loadValues()
        values[account] = nil
        try saveValues(values)
    }

    private func loadValues() throws -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }

        if data.isEmpty {
            return [:]
        }

        guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw Error.invalidEncoding
        }
        return decoded
    }

    private func saveValues(_ values: [String: String]) throws {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: [.atomic])
    }
}

@MainActor
@Observable
final class EnhancedSourceCredentialStore {
    private let secretStore: any SecretStoring
    private let userDefaults: UserDefaults
    private var valuesByKind: [EnhancedCredentialKind: String] = [:]
    private var loadErrorsByKind: [EnhancedCredentialKind: String] = [:]

    init(
        secretStore: (any SecretStoring)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.secretStore = secretStore ?? LocalSecretStore(service: "com.thomas.currency-tracker")
        self.userDefaults = userDefaults
        migrateLegacyCredentialsIfNeeded()
        reload()
    }

    var configuration: EnhancedSourceConfiguration {
        EnhancedSourceConfiguration(
            twelveDataAPIKey: storedValue(for: .twelveData),
            openExchangeRatesAppID: storedValue(for: .openExchangeRates)
        )
    }

    func hasStoredValue(for kind: EnhancedCredentialKind) -> Bool {
        !storedValue(for: kind).isEmpty
    }

    func storedValue(for kind: EnhancedCredentialKind) -> String {
        valuesByKind[kind] ?? ""
    }

    func lastLoadError(for kind: EnhancedCredentialKind) -> String? {
        loadErrorsByKind[kind]
    }

    func save(_ value: String, for kind: EnhancedCredentialKind) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            try secretStore.delete(account: kind.account)
            userDefaults.removeObject(forKey: kind.legacyDefaultsKey)
            valuesByKind[kind] = ""
        } else {
            try secretStore.write(trimmedValue, account: kind.account)
            userDefaults.removeObject(forKey: kind.legacyDefaultsKey)
            valuesByKind[kind] = trimmedValue
        }
    }

    func deleteValue(for kind: EnhancedCredentialKind) throws {
        try secretStore.delete(account: kind.account)
        userDefaults.removeObject(forKey: kind.legacyDefaultsKey)
        valuesByKind[kind] = ""
    }

    func reload() {
        for kind in EnhancedCredentialKind.allCases {
            do {
                if let storedSecret = try secretStore.read(account: kind.account)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !storedSecret.isEmpty {
                    valuesByKind[kind] = storedSecret
                    loadErrorsByKind[kind] = nil
                    userDefaults.removeObject(forKey: kind.legacyDefaultsKey)
                    continue
                }
            } catch {
                loadErrorsByKind[kind] = "本地凭证存储当前不可用，请稍后重试"
                valuesByKind[kind] = legacyValue(for: kind) ?? ""
                continue
            }

            loadErrorsByKind[kind] = nil
            valuesByKind[kind] = legacyValue(for: kind) ?? ""
        }
    }

    private func migrateLegacyCredentialsIfNeeded() {
        for kind in EnhancedCredentialKind.allCases {
            guard let legacyValue = legacyValue(for: kind) else {
                userDefaults.removeObject(forKey: kind.legacyDefaultsKey)
                continue
            }

            if let existingSecretValue = (try? secretStore.read(account: kind.account))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !existingSecretValue.isEmpty {
                userDefaults.removeObject(forKey: kind.legacyDefaultsKey)
                continue
            }

            do {
                try secretStore.write(legacyValue, account: kind.account)
                userDefaults.removeObject(forKey: kind.legacyDefaultsKey)
            } catch {
                continue
            }
        }
    }

    private func legacyValue(for kind: EnhancedCredentialKind) -> String? {
        guard let legacyValue = userDefaults.string(forKey: kind.legacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyValue.isEmpty else {
            return nil
        }

        return legacyValue
    }
}
