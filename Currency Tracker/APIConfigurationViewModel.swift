//
//  APIConfigurationViewModel.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Observation
import SwiftUI

enum APIFieldPhase: Equatable, Sendable {
    case empty
    case saved
    case editing
    case saving
    case success
    case failure(String)

    var statusText: String {
        switch self {
        case .empty:
            "未填写"
        case .saved:
            "已保存"
        case .editing:
            "编辑中"
        case .saving:
            "保存中"
        case .success:
            "验证成功"
        case .failure(let message):
            message
        }
    }

    var tintColor: Color {
        switch self {
        case .empty, .saved, .editing:
            .secondary
        case .saving:
            Color(red: 0.08, green: 0.43, blue: 0.74)
        case .success:
            Color(red: 0.09, green: 0.53, blue: 0.32)
        case .failure:
            Color(red: 0.74, green: 0.20, blue: 0.18)
        }
    }
}

struct APIFieldState: Equatable, Sendable {
    let kind: EnhancedCredentialKind
    var draftValue: String
    var isEditing: Bool
    var isRevealed: Bool
    var phase: APIFieldPhase

    var hasStoredValue: Bool {
        !draftValue.isEmpty
    }

    var buttonTitle: String {
        if isEditing {
            return "保存"
        }

        return hasStoredValue ? "已保存" : "编辑"
    }
}

@MainActor
@Observable
final class APIConfigurationViewModel {
    var twelveDataField: APIFieldState
    var openExchangeRatesField: APIFieldState

    private let credentialStore: EnhancedSourceCredentialStore
    private let service: any APIValidationServicing
    private let logHandler: @MainActor (RefreshLogEntry.Level, String) -> Void

    init(
        credentialStore: EnhancedSourceCredentialStore,
        service: any APIValidationServicing,
        logHandler: @escaping @MainActor (RefreshLogEntry.Level, String) -> Void
    ) {
        self.credentialStore = credentialStore
        self.service = service
        self.logHandler = logHandler
        self.twelveDataField = APIFieldState(kind: .twelveData, draftValue: "", isEditing: false, isRevealed: false, phase: .empty)
        self.openExchangeRatesField = APIFieldState(kind: .openExchangeRates, draftValue: "", isEditing: false, isRevealed: false, phase: .empty)
        reloadFromStore()
    }

    func reloadFromStore() {
        credentialStore.reload()
        syncField(.twelveData, phaseOverride: nil, keepEditing: false)
        syncField(.openExchangeRates, phaseOverride: nil, keepEditing: false)
        applyStoreLoadIssueIfNeeded(for: .twelveData)
        applyStoreLoadIssueIfNeeded(for: .openExchangeRates)
    }

    func field(for kind: EnhancedCredentialKind) -> APIFieldState {
        switch kind {
        case .twelveData:
            twelveDataField
        case .openExchangeRates:
            openExchangeRatesField
        }
    }

    func updateDraft(_ value: String, for kind: EnhancedCredentialKind) {
        mutateField(kind) {
            $0.draftValue = value
            if $0.isEditing {
                $0.phase = .editing
            }
        }
    }

    func toggleReveal(for kind: EnhancedCredentialKind) {
        mutateField(kind) {
            guard !$0.draftValue.isEmpty else {
                return
            }

            $0.isRevealed.toggle()
        }
    }

    func beginEditing(_ kind: EnhancedCredentialKind) {
        mutateField(kind) {
            $0.isEditing = true
            $0.phase = .editing
        }
    }

    func performPrimaryAction(for kind: EnhancedCredentialKind) async {
        if field(for: kind).isEditing {
            await save(kind)
        } else {
            beginEditing(kind)
        }
    }

    func save(_ kind: EnhancedCredentialKind) async {
        let trimmedValue = field(for: kind).draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateField(kind) {
            $0.draftValue = trimmedValue
            $0.phase = .saving
        }

        if trimmedValue.isEmpty {
            do {
                try credentialStore.deleteValue(for: kind)
                syncField(kind, phaseOverride: .empty, keepEditing: false)
                logHandler(.info, "\(kind.displayName) 凭证已清除")
            } catch {
                mutateField(kind) {
                    $0.isEditing = true
                    $0.phase = .failure("保存失败，请重试")
                }
                logHandler(.warning, "\(kind.displayName) 清除失败：\(error.localizedDescription)")
            }
            return
        }

        let validationMessage = await validationFailureMessage(for: kind, value: trimmedValue)

        if let validationMessage {
            mutateField(kind) {
                $0.isEditing = true
                $0.phase = .failure(validationMessage)
            }
            logHandler(.warning, "\(kind.displayName) 保存后验证失败")
            return
        }

        do {
            try credentialStore.save(trimmedValue, for: kind)
            syncField(kind, phaseOverride: .success, keepEditing: false)
            logHandler(.info, "\(kind.displayName) 保存后验证成功")
        } catch {
            mutateField(kind) {
                $0.isEditing = true
                $0.phase = .failure("保存失败，请重试")
            }
            logHandler(.warning, "\(kind.displayName) 写入本地凭证存储失败：\(error.localizedDescription)")
        }
    }

    private func validationFailureMessage(for kind: EnhancedCredentialKind, value: String) async -> String? {
        switch kind {
        case .twelveData:
            await service.validateTwelveDataAPIKey(value)
        case .openExchangeRates:
            await service.validateOpenExchangeRatesAppID(value)
        }
    }

    private func syncField(
        _ kind: EnhancedCredentialKind,
        phaseOverride: APIFieldPhase?,
        keepEditing: Bool
    ) {
        let storedValue = credentialStore.storedValue(for: kind)
        mutateField(kind) {
            $0.draftValue = storedValue
            $0.isEditing = keepEditing
            $0.isRevealed = false
            $0.phase = phaseOverride ?? (storedValue.isEmpty ? .empty : .saved)
        }
    }

    private func mutateField(_ kind: EnhancedCredentialKind, transform: (inout APIFieldState) -> Void) {
        switch kind {
        case .twelveData:
            transform(&twelveDataField)
        case .openExchangeRates:
            transform(&openExchangeRatesField)
        }
    }

    private func applyStoreLoadIssueIfNeeded(for kind: EnhancedCredentialKind) {
        guard credentialStore.storedValue(for: kind).isEmpty,
              let message = credentialStore.lastLoadError(for: kind) else {
            return
        }

        mutateField(kind) {
            guard !$0.isEditing else {
                return
            }

            $0.phase = .failure(message)
        }
    }
}
