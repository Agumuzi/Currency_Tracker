//
//  ExchangeRateService.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

protocol APIValidationServicing: Sendable {
    func validateCredential(_ credential: String, for kind: EnhancedCredentialKind) async -> String?
}

nonisolated private enum ExchangeRateServiceConstants {
    static let historicalLookbackDays = 365
    static let publicNonRubSources: [ExchangeSource] = [.ecb, .frankfurter, .floatRates, .currencyAPI]
    static let snapshotSourceOrder: [ExchangeSource] = [.twelveData, .exchangeRateAPI, .openExchangeRates, .fixer, .currencyLayer, .cbr, .ecb, .frankfurter, .floatRates, .currencyAPI]
    static let twelveDataRequestHeaders = ["X-API-Version": "last"]
    static let rateLimitCooldown: TimeInterval = 15 * 60
    static let authenticationCooldown: TimeInterval = 30 * 60
    static let standardTimeout: TimeInterval = 5
    static let fallbackTimeout: TimeInterval = 4
    static let validationTimeout: TimeInterval = 4
}

private struct SnapshotGroupFetchResult: Sendable {
    var snapshots: [CurrencySnapshot]
    var errors: [String]
    var responseDates: Set<String>
    var hadFailure: Bool
}

private struct HistoricalGroupFetchResult: Sendable {
    var historyByPairID: [String: [TrendPoint]]
    var errors: [String]
}

private func makeExchangeRateURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = ExchangeRateServiceConstants.standardTimeout
    configuration.timeoutIntervalForResource = ExchangeRateServiceConstants.standardTimeout * 2
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpAdditionalHeaders = [
        "Accept": "application/json, text/plain, */*",
        "User-Agent": "CurrencyTracker/1.0"
    ]
    return URLSession(configuration: configuration)
}

actor ExchangeRateService: APIValidationServicing {
    private let urlSession: URLSession
    private var cbrCurrencyIDByCode: [String: String]?
    private var sourceCooldownUntil: [ExchangeSource: Date] = [:]
    private var unsupportedPairsBySource: [ExchangeSource: Set<String>] = [:]
    private var enhancedConfigurationSignature = ""

    init(urlSession: URLSession? = nil) {
        self.urlSession = urlSession ?? makeExchangeRateURLSession()
    }

    func fetchSnapshots(
        for pairs: [CurrencyPair],
        configuration: EnhancedSourceConfiguration = .empty
    ) async -> ExchangeFetchResult {
        syncEnhancedStateIfNeeded(for: configuration)

        guard !pairs.isEmpty else {
            return ExchangeFetchResult(
                snapshots: [],
                errors: [],
                sourceStatuses: ExchangeRateServiceConstants.snapshotSourceOrder.map {
                    SourceStatus(source: $0, state: .idle, message: "当前未使用 \($0.displayName)", timestamp: .now)
                },
                logs: []
            )
        }

        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var sourceStatuses: [SourceStatus] = []
        var logs: [DispatchLogEntry] = []
        var remainingPairs = pairs

        let twelveDataResult = await fetchTwelveDataSnapshotsIfNeeded(
            for: remainingPairs,
            apiKey: configuration.twelveDataAPIKey
        )
        snapshots.append(contentsOf: twelveDataResult.snapshots)
        errors.append(contentsOf: twelveDataResult.errors)
        sourceStatuses.append(twelveDataResult.sourceStatus)
        logs.append(contentsOf: twelveDataResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(twelveDataResult.snapshots.map(\.id)))

        let exchangeRateAPIResult = await fetchExchangeRateAPISnapshotsIfNeeded(
            for: remainingPairs,
            apiKey: configuration.exchangeRateAPIKey
        )
        snapshots.append(contentsOf: exchangeRateAPIResult.snapshots)
        errors.append(contentsOf: exchangeRateAPIResult.errors)
        sourceStatuses.append(exchangeRateAPIResult.sourceStatus)
        logs.append(contentsOf: exchangeRateAPIResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(exchangeRateAPIResult.snapshots.map(\.id)))

        let openExchangeRatesResult = await fetchOpenExchangeRatesSnapshotsIfNeeded(
            for: remainingPairs,
            appID: configuration.openExchangeRatesAppID
        )
        snapshots.append(contentsOf: openExchangeRatesResult.snapshots)
        errors.append(contentsOf: openExchangeRatesResult.errors)
        sourceStatuses.append(openExchangeRatesResult.sourceStatus)
        logs.append(contentsOf: openExchangeRatesResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(openExchangeRatesResult.snapshots.map(\.id)))

        let fixerResult = await fetchFixerSnapshotsIfNeeded(
            for: remainingPairs,
            apiKey: configuration.fixerAPIKey
        )
        snapshots.append(contentsOf: fixerResult.snapshots)
        errors.append(contentsOf: fixerResult.errors)
        sourceStatuses.append(fixerResult.sourceStatus)
        logs.append(contentsOf: fixerResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(fixerResult.snapshots.map(\.id)))

        let currencyLayerResult = await fetchCurrencyLayerSnapshotsIfNeeded(
            for: remainingPairs,
            apiKey: configuration.currencyLayerAPIKey
        )
        snapshots.append(contentsOf: currencyLayerResult.snapshots)
        errors.append(contentsOf: currencyLayerResult.errors)
        sourceStatuses.append(currencyLayerResult.sourceStatus)
        logs.append(contentsOf: currencyLayerResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(currencyLayerResult.snapshots.map(\.id)))

        let rubPairs = remainingPairs.filter { $0.requiresCBR }
        let nonRubPairs = remainingPairs.filter { !$0.requiresCBR }

        async let cbrResult: ExchangeFetchResult = rubPairs.isEmpty
            ? ExchangeFetchResult(
                snapshots: [],
                errors: [],
                sourceStatuses: [
                    SourceStatus(source: .cbr, state: .idle, message: "当前未使用 CBR", timestamp: .now)
                ],
                logs: [
                    DispatchLogEntry(level: .info, message: "CBR 已跳过：当前没有待补全的 RUB 货币对")
                ]
            )
            : fetchCBRResult(for: rubPairs)

        async let nonRubResult: ExchangeFetchResult = nonRubPairs.isEmpty
            ? ExchangeFetchResult(
                snapshots: [],
                errors: [],
                sourceStatuses: ExchangeRateServiceConstants.publicNonRubSources.map {
                    SourceStatus(source: $0, state: .idle, message: "当前未使用 \($0.displayName)", timestamp: .now)
                },
                logs: [
                    DispatchLogEntry(level: .info, message: "公共非 RUB 来源已跳过：当前没有待补全的非 RUB 货币对")
                ]
            )
            : fetchNonRubSnapshots(for: nonRubPairs)

        let cbrResultValue = await cbrResult
        let nonRubResultValue = await nonRubResult

        snapshots.append(contentsOf: cbrResultValue.snapshots)
        snapshots.append(contentsOf: nonRubResultValue.snapshots)
        errors.append(contentsOf: cbrResultValue.errors)
        errors.append(contentsOf: nonRubResultValue.errors)
        sourceStatuses.append(contentsOf: cbrResultValue.sourceStatuses)
        sourceStatuses.append(contentsOf: nonRubResultValue.sourceStatuses)
        logs.append(contentsOf: cbrResultValue.logs)
        logs.append(contentsOf: nonRubResultValue.logs)

        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(cbrResultValue.snapshots.map(\.id) + nonRubResultValue.snapshots.map(\.id)))

        if !remainingPairs.isEmpty {
            let remainingText = remainingPairs.map(\.compactLabel).joined(separator: "、")
            errors.append("所有来源 fallback 后仍缺少 \(remainingText)")
            logs.append(DispatchLogEntry(level: .warning, message: "仍有货币对未命中在线来源，将继续保留缓存：\(remainingText)"))
        }

        return ExchangeFetchResult(
            snapshots: snapshots,
            errors: errors,
            sourceStatuses: sortStatuses(sourceStatuses),
            logs: logs
        )
    }

    func fetchHistoricalSeries(for pairs: [CurrencyPair]) async -> HistoricalFetchResult {
        let rubPairs = pairs.filter { $0.requiresCBR }
        let nonRubPairs = pairs.filter { !$0.requiresCBR }

        async let cbrResult: HistoricalFetchResult = rubPairs.isEmpty
            ? HistoricalFetchResult(historyByPairID: [:], errors: [])
            : fetchCBRHistoricalSeries(for: rubPairs)

        async let nonRubResult: HistoricalFetchResult = nonRubPairs.isEmpty
            ? HistoricalFetchResult(historyByPairID: [:], errors: [])
            : fetchNonRubHistoricalSeries(for: nonRubPairs)

        let cbrResultValue = await cbrResult
        let nonRubResultValue = await nonRubResult

        return HistoricalFetchResult(
            historyByPairID: cbrResultValue.historyByPairID.merging(nonRubResultValue.historyByPairID) { _, new in new },
            errors: cbrResultValue.errors + nonRubResultValue.errors
        )
    }

    func validateCredential(_ credential: String, for kind: EnhancedCredentialKind) async -> String? {
        switch kind {
        case .twelveData:
            return await validateTwelveDataAPIKey(credential)
        case .exchangeRateAPI:
            return await validateExchangeRateAPIKey(credential)
        case .openExchangeRates:
            return await validateOpenExchangeRatesAppID(credential)
        case .fixer:
            return await validateFixerAPIKey(credential)
        case .currencyLayer:
            return await validateCurrencyLayerAPIKey(credential)
        }
    }

    func validateTwelveDataAPIKey(_ apiKey: String) async -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        do {
            var components = URLComponents(string: "https://api.twelvedata.com/exchange_rate")!
            components.queryItems = [
                URLQueryItem(name: "symbol", value: "USD/EUR"),
                URLQueryItem(name: "apikey", value: trimmedKey)
            ]

            let data = try await responseData(
                from: components.url!,
                retryCount: 0,
                timeoutInterval: ExchangeRateServiceConstants.validationTimeout,
                additionalHeaders: ExchangeRateServiceConstants.twelveDataRequestHeaders
            )
            _ = try TwelveDataParser.parseExchangeRate(from: data)
            return nil
        } catch {
            switch mapTwelveDataError(error) {
            case .authenticationFailed:
                return "验证失败，请检查 key"
            case .rateLimited:
                return "验证失败，当前额度不可用"
            case .unsupportedPair, .noData, .transport:
                return "验证失败，请稍后重试"
            }
        }
    }

    func validateExchangeRateAPIKey(_ apiKey: String) async -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        do {
            let requestURL = URL(string: "https://v6.exchangerate-api.com/v6/\(trimmedKey)/latest/USD")!
            let data = try await responseData(
                from: requestURL,
                retryCount: 0,
                timeoutInterval: ExchangeRateServiceConstants.validationTimeout
            )
            _ = try ExchangeRateAPIParser.parseLatest(from: data)
            return nil
        } catch {
            switch mapGenericEnhancedProviderError(error) {
            case .authenticationFailed:
                return "验证失败，请检查 key"
            case .rateLimited:
                return "验证失败，当前额度不可用"
            case .unsupportedPair, .noData, .transport:
                return "验证失败，请稍后重试"
            }
        }
    }

    func validateOpenExchangeRatesAppID(_ appID: String) async -> String? {
        let trimmedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAppID.isEmpty else {
            return nil
        }

        do {
            var components = URLComponents(string: "https://openexchangerates.org/api/latest.json")!
            components.queryItems = [
                URLQueryItem(name: "app_id", value: trimmedAppID),
                URLQueryItem(name: "symbols", value: "EUR"),
                URLQueryItem(name: "prettyprint", value: "false")
            ]

            let data = try await responseData(
                from: components.url!,
                retryCount: 0,
                timeoutInterval: ExchangeRateServiceConstants.validationTimeout
            )
            _ = try OpenExchangeRatesParser.parseLatest(from: data)
            return nil
        } catch {
            switch mapOpenExchangeRatesError(error) {
            case .authenticationFailed:
                return "验证失败，请检查 key"
            case .rateLimited:
                return "验证失败，当前额度不可用"
            case .unsupportedPair, .noData, .transport:
                return "验证失败，请稍后重试"
            }
        }
    }

    func validateFixerAPIKey(_ apiKey: String) async -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        do {
            var components = URLComponents(string: "https://data.fixer.io/api/latest")!
            components.queryItems = [
                URLQueryItem(name: "access_key", value: trimmedKey),
                URLQueryItem(name: "symbols", value: "USD")
            ]
            let data = try await responseData(
                from: components.url!,
                retryCount: 0,
                timeoutInterval: ExchangeRateServiceConstants.validationTimeout
            )
            _ = try FixerParser.parseLatest(from: data)
            return nil
        } catch {
            switch mapGenericEnhancedProviderError(error) {
            case .authenticationFailed:
                return "验证失败，请检查 key"
            case .rateLimited:
                return "验证失败，当前额度不可用"
            case .unsupportedPair, .noData, .transport:
                return "验证失败，请稍后重试"
            }
        }
    }

    func validateCurrencyLayerAPIKey(_ apiKey: String) async -> String? {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return nil
        }

        do {
            var components = URLComponents(string: "https://api.currencylayer.com/live")!
            components.queryItems = [
                URLQueryItem(name: "access_key", value: trimmedKey),
                URLQueryItem(name: "currencies", value: "EUR")
            ]
            let data = try await responseData(
                from: components.url!,
                retryCount: 0,
                timeoutInterval: ExchangeRateServiceConstants.validationTimeout
            )
            _ = try CurrencyLayerParser.parseLive(from: data)
            return nil
        } catch {
            switch mapGenericEnhancedProviderError(error) {
            case .authenticationFailed:
                return "验证失败，请检查 key"
            case .rateLimited:
                return "验证失败，当前额度不可用"
            case .unsupportedPair, .noData, .transport:
                return "验证失败，请稍后重试"
            }
        }
    }

    private func fetchNonRubSnapshots(for pairs: [CurrencyPair]) async -> ExchangeFetchResult {
        guard !pairs.isEmpty else {
            return ExchangeFetchResult(
                snapshots: [],
                errors: [],
                sourceStatuses: ExchangeRateServiceConstants.publicNonRubSources.map {
                    SourceStatus(source: $0, state: .idle, message: "当前未使用 \($0.displayName)", timestamp: .now)
                },
                logs: []
            )
        }

        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var sourceStatuses: [SourceStatus] = []
        var logs: [DispatchLogEntry] = []
        var remainingPairs = pairs

        let ecbResult = await fetchECBSnapshots(for: remainingPairs)
        snapshots.append(contentsOf: ecbResult.snapshots)
        errors.append(contentsOf: ecbResult.errors)
        sourceStatuses.append(ecbResult.sourceStatus)
        logs.append(contentsOf: ecbResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(ecbResult.snapshots.map(\.id)))

        if remainingPairs.isEmpty {
            sourceStatuses.append(contentsOf: skippedStatuses(for: [.frankfurter, .floatRates, .currencyAPI], message: "已由 ECB Direct 覆盖"))
            logs.append(DispatchLogEntry(level: .info, message: "公共来源已命中 ECB Direct，后续公共来源已跳过"))
            return ExchangeFetchResult(snapshots: snapshots, errors: errors, sourceStatuses: sourceStatuses, logs: logs)
        }

        let frankfurterResult = await fetchFrankfurterSnapshots(for: remainingPairs)
        snapshots.append(contentsOf: frankfurterResult.snapshots)
        errors.append(contentsOf: frankfurterResult.errors)
        sourceStatuses.append(frankfurterResult.sourceStatus)
        logs.append(contentsOf: frankfurterResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(frankfurterResult.snapshots.map(\.id)))

        if remainingPairs.isEmpty {
            sourceStatuses.append(contentsOf: skippedStatuses(for: [.floatRates, .currencyAPI], message: "已由更高优先级来源覆盖"))
            logs.append(DispatchLogEntry(level: .info, message: "公共来源已通过 Frankfurter 补齐，后续公共来源已跳过"))
            return ExchangeFetchResult(snapshots: snapshots, errors: errors, sourceStatuses: sourceStatuses, logs: logs)
        }

        let floatRatesResult = await fetchFloatRatesSnapshots(for: remainingPairs)
        snapshots.append(contentsOf: floatRatesResult.snapshots)
        errors.append(contentsOf: floatRatesResult.errors)
        sourceStatuses.append(floatRatesResult.sourceStatus)
        logs.append(contentsOf: floatRatesResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(floatRatesResult.snapshots.map(\.id)))

        if remainingPairs.isEmpty {
            sourceStatuses.append(contentsOf: skippedStatuses(for: [.currencyAPI], message: "已由更高优先级来源覆盖"))
            logs.append(DispatchLogEntry(level: .info, message: "公共来源已通过 FloatRates 补齐，Currency API 已跳过"))
            return ExchangeFetchResult(snapshots: snapshots, errors: errors, sourceStatuses: sourceStatuses, logs: logs)
        }

        let currencyAPIResult = await fetchCurrencyAPISnapshots(for: remainingPairs)
        snapshots.append(contentsOf: currencyAPIResult.snapshots)
        errors.append(contentsOf: currencyAPIResult.errors)
        sourceStatuses.append(currencyAPIResult.sourceStatus)
        logs.append(contentsOf: currencyAPIResult.logs)
        remainingPairs = unresolvedPairs(from: remainingPairs, resolvedPairIDs: Set(currencyAPIResult.snapshots.map(\.id)))

        if !remainingPairs.isEmpty {
            errors.append("多源 fallback 后仍缺少 \(remainingPairs.map(\.compactLabel).joined(separator: "、"))")
            logs.append(DispatchLogEntry(level: .warning, message: "公共非 RUB 来源未能补齐：\(remainingPairs.map(\.compactLabel).joined(separator: "、"))"))
        }

        return ExchangeFetchResult(snapshots: snapshots, errors: errors, sourceStatuses: sourceStatuses, logs: logs)
    }

    private func fetchNonRubHistoricalSeries(for pairs: [CurrencyPair]) async -> HistoricalFetchResult {
        guard !pairs.isEmpty else {
            return HistoricalFetchResult(historyByPairID: [:], errors: [])
        }

        let ecbResult = await fetchECBHistoricalSeries(for: pairs)
        let unresolvedPairs = pairs.filter { ecbResult.historyByPairID[$0.id] == nil }

        guard !unresolvedPairs.isEmpty else {
            return ecbResult
        }

        let frankfurterResult = await fetchFrankfurterHistoricalSeries(for: unresolvedPairs)

        return HistoricalFetchResult(
            historyByPairID: ecbResult.historyByPairID.merging(frankfurterResult.historyByPairID) { current, _ in current },
            errors: ecbResult.errors + frankfurterResult.errors
        )
    }

    private func unresolvedPairs(from pairs: [CurrencyPair], resolvedPairIDs: Set<String>) -> [CurrencyPair] {
        pairs.filter { !resolvedPairIDs.contains($0.id) }
    }

    private func sortStatuses(_ statuses: [SourceStatus]) -> [SourceStatus] {
        let order = Dictionary(uniqueKeysWithValues: ExchangeRateServiceConstants.snapshotSourceOrder.enumerated().map { ($1, $0) })
        return statuses.sorted { lhs, rhs in
            let left = order[lhs.source] ?? Int.max
            let right = order[rhs.source] ?? Int.max
            if left == right {
                return lhs.timestamp > rhs.timestamp
            }
            return left < right
        }
    }

    private func skippedStatuses(for sources: [ExchangeSource], message: String) -> [SourceStatus] {
        sources.map {
            SourceStatus(source: $0, state: .idle, message: message, timestamp: .now)
        }
    }

    private func syncEnhancedStateIfNeeded(for configuration: EnhancedSourceConfiguration) {
        let signature = EnhancedCredentialKind.allCases
            .map { configuration.credential(for: $0) }
            .joined(separator: "|")
        guard signature != enhancedConfigurationSignature else {
            return
        }

        enhancedConfigurationSignature = signature
        for source in ExchangeRateServiceConstants.snapshotSourceOrder {
            sourceCooldownUntil[source] = nil
            unsupportedPairsBySource[source] = []
        }
    }

    private func isSourceCoolingDown(_ source: ExchangeSource, now: Date = .now) -> Date? {
        guard let until = sourceCooldownUntil[source], until > now else {
            sourceCooldownUntil[source] = nil
            return nil
        }

        return until
    }

    private func beginCooldown(for source: ExchangeSource, duration: TimeInterval) {
        sourceCooldownUntil[source] = Date().addingTimeInterval(duration)
    }

    private func markUnsupported(_ pair: CurrencyPair, for source: ExchangeSource) {
        unsupportedPairsBySource[source, default: []].insert(pair.id)
    }

    private func eligiblePairs(for source: ExchangeSource, from pairs: [CurrencyPair]) -> [CurrencyPair] {
        let unsupported = unsupportedPairsBySource[source] ?? []
        return pairs.filter { unsupported.contains($0.id) == false }
    }

    private func skippedEnhancedProviderResult(
        for source: ExchangeSource,
        message: String,
        level: RefreshLogEntry.Level = .info
    ) -> ProviderFetchResult {
        ProviderFetchResult(
            snapshots: [],
            errors: [],
            sourceStatus: SourceStatus(source: source, state: .idle, message: message, timestamp: .now),
            logs: [
                DispatchLogEntry(level: level, message: "\(source.displayName) 已跳过：\(message)")
            ]
        )
    }

    private func fetchTwelveDataSnapshotsIfNeeded(
        for pairs: [CurrencyPair],
        apiKey: String
    ) async -> ProviderFetchResult {
        guard !pairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .twelveData, message: "当前没有待补全的货币对")
        }

        guard !apiKey.isEmpty else {
            return skippedEnhancedProviderResult(for: .twelveData, message: "未填写 API key，继续使用默认公共数据源")
        }

        if let cooldownUntil = isSourceCoolingDown(.twelveData) {
            let timeText = ExchangeFormatter.time.string(from: cooldownUntil)
            return skippedEnhancedProviderResult(for: .twelveData, message: "处于冷却中，\(timeText) 后重试", level: .warning)
        }

        let eligiblePairs = eligiblePairs(for: .twelveData, from: pairs)
        guard !eligiblePairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .twelveData, message: "当前剩余币对已判定为暂不支持")
        }

        return await fetchTwelveDataSnapshots(for: eligiblePairs, apiKey: apiKey)
    }

    private func fetchExchangeRateAPISnapshotsIfNeeded(
        for pairs: [CurrencyPair],
        apiKey: String
    ) async -> ProviderFetchResult {
        guard !pairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .exchangeRateAPI, message: "当前没有待补全的货币对")
        }

        guard !apiKey.isEmpty else {
            return skippedEnhancedProviderResult(for: .exchangeRateAPI, message: "未填写 API Key，继续使用默认公共数据源")
        }

        if let cooldownUntil = isSourceCoolingDown(.exchangeRateAPI) {
            let timeText = ExchangeFormatter.time.string(from: cooldownUntil)
            return skippedEnhancedProviderResult(for: .exchangeRateAPI, message: "处于冷却中，\(timeText) 后重试", level: .warning)
        }

        let eligiblePairs = eligiblePairs(for: .exchangeRateAPI, from: pairs)
        guard !eligiblePairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .exchangeRateAPI, message: "当前剩余币对已判定为暂不支持")
        }

        return await fetchExchangeRateAPISnapshots(for: eligiblePairs, apiKey: apiKey)
    }

    private func fetchOpenExchangeRatesSnapshotsIfNeeded(
        for pairs: [CurrencyPair],
        appID: String
    ) async -> ProviderFetchResult {
        guard !pairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .openExchangeRates, message: "当前没有待补全的货币对")
        }

        guard !appID.isEmpty else {
            return skippedEnhancedProviderResult(for: .openExchangeRates, message: "未填写 App ID，继续使用默认公共数据源")
        }

        if let cooldownUntil = isSourceCoolingDown(.openExchangeRates) {
            let timeText = ExchangeFormatter.time.string(from: cooldownUntil)
            return skippedEnhancedProviderResult(for: .openExchangeRates, message: "处于冷却中，\(timeText) 后重试", level: .warning)
        }

        let eligiblePairs = eligiblePairs(for: .openExchangeRates, from: pairs)
        guard !eligiblePairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .openExchangeRates, message: "当前剩余币对已判定为暂不支持")
        }

        return await fetchOpenExchangeRatesSnapshots(for: eligiblePairs, appID: appID)
    }

    private func fetchFixerSnapshotsIfNeeded(
        for pairs: [CurrencyPair],
        apiKey: String
    ) async -> ProviderFetchResult {
        guard !pairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .fixer, message: "当前没有待补全的货币对")
        }

        guard !apiKey.isEmpty else {
            return skippedEnhancedProviderResult(for: .fixer, message: "未填写 API Key，继续使用默认公共数据源")
        }

        if let cooldownUntil = isSourceCoolingDown(.fixer) {
            let timeText = ExchangeFormatter.time.string(from: cooldownUntil)
            return skippedEnhancedProviderResult(for: .fixer, message: "处于冷却中，\(timeText) 后重试", level: .warning)
        }

        let eligiblePairs = eligiblePairs(for: .fixer, from: pairs)
        guard !eligiblePairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .fixer, message: "当前剩余币对已判定为暂不支持")
        }

        return await fetchFixerSnapshots(for: eligiblePairs, apiKey: apiKey)
    }

    private func fetchCurrencyLayerSnapshotsIfNeeded(
        for pairs: [CurrencyPair],
        apiKey: String
    ) async -> ProviderFetchResult {
        guard !pairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .currencyLayer, message: "当前没有待补全的货币对")
        }

        guard !apiKey.isEmpty else {
            return skippedEnhancedProviderResult(for: .currencyLayer, message: "未填写 API Key，继续使用默认公共数据源")
        }

        if let cooldownUntil = isSourceCoolingDown(.currencyLayer) {
            let timeText = ExchangeFormatter.time.string(from: cooldownUntil)
            return skippedEnhancedProviderResult(for: .currencyLayer, message: "处于冷却中，\(timeText) 后重试", level: .warning)
        }

        let eligiblePairs = eligiblePairs(for: .currencyLayer, from: pairs)
        guard !eligiblePairs.isEmpty else {
            return skippedEnhancedProviderResult(for: .currencyLayer, message: "当前剩余币对已判定为暂不支持")
        }

        return await fetchCurrencyLayerSnapshots(for: eligiblePairs, apiKey: apiKey)
    }

    private func fetchCBRHistoricalSeries(for pairs: [CurrencyPair]) async -> HistoricalFetchResult {
        let groups = Dictionary(grouping: pairs, by: \.baseCode)
        var historyByPairID: [String: [TrendPoint]] = [:]
        var errors: [String] = []
        let range = historicalRequestRange()

        do {
            let currencyIDs = try await cbrCurrencyReference()

            for (baseCode, group) in groups {
                guard let currencyID = currencyIDs[baseCode] else {
                    errors.append("CBR 历史接口缺少 \(baseCode) 的货币映射")
                    continue
                }

                do {
                    let requestURL = URL(string: "https://www.cbr.ru/scripts/XML_dynamic.asp?date_req1=\(SourceDateParser.cbrQueryString(from: range.start))&date_req2=\(SourceDateParser.cbrQueryString(from: range.end))&VAL_NM_RQ=\(currencyID)")!
                    let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
                    let unitPoints = try CBRDynamicParser.parsePoints(from: data)

                    guard !unitPoints.isEmpty else {
                        errors.append("CBR 历史接口未返回 \(baseCode) 数据")
                        continue
                    }

                    for pair in group {
                        historyByPairID[pair.id] = unitPoints.map {
                            TrendPoint(timestamp: $0.timestamp, value: $0.value * Double(pair.baseAmount))
                        }
                    }
                } catch {
                    errors.append("CBR 历史数据刷新失败：\(baseCode)")
                }
            }
        } catch {
            errors.append("CBR 历史货币映射加载失败")
        }

        return HistoricalFetchResult(historyByPairID: historyByPairID, errors: errors)
    }

    private func fetchECBHistoricalSeries(for pairs: [CurrencyPair]) async -> HistoricalFetchResult {
        let range = historicalRequestRange()
        let from = SourceDateParser.isoQueryString(from: range.start)
        let to = SourceDateParser.isoQueryString(from: range.end)
        let requestedCurrencies = Set(pairs.flatMap { [$0.baseCode, $0.quoteCode] }.filter { $0 != "EUR" }).sorted()

        guard !requestedCurrencies.isEmpty else {
            return HistoricalFetchResult(historyByPairID: [:], errors: ["ECB 直连历史缺少可查询币种"])
        }

        do {
            let requestURL = URL(string: "https://data-api.ecb.europa.eu/service/data/EXR/D.\(requestedCurrencies.joined(separator: "+")).EUR.SP00.A?startPeriod=\(from)&endPeriod=\(to)&format=jsondata&detail=dataonly")!
            let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
            let seriesByCurrency = try ECBEXRParser.parseSeriesByCurrency(from: data)

            var historyByPairID: [String: [TrendPoint]] = [:]
            var errors: [String] = []

            for pair in pairs {
                let points = crossSeries(for: pair, using: seriesByCurrency)

                if points.isEmpty {
                    errors.append("ECB 直连历史缺少 \(pair.baseCode)/\(pair.quoteCode)")
                } else {
                    historyByPairID[pair.id] = points
                }
            }

            return HistoricalFetchResult(historyByPairID: historyByPairID, errors: errors)
        } catch {
            return HistoricalFetchResult(historyByPairID: [:], errors: ["ECB 直连历史刷新失败"])
        }
    }

    private func fetchFrankfurterHistoricalSeries(for pairs: [CurrencyPair]) async -> HistoricalFetchResult {
        let groups = Dictionary(grouping: pairs, by: \.baseCode)
        var historyByPairID: [String: [TrendPoint]] = [:]
        var errors: [String] = []
        let range = historicalRequestRange()
        let from = SourceDateParser.isoQueryString(from: range.start)
        let to = SourceDateParser.isoQueryString(from: range.end)

        await withTaskGroup(of: HistoricalGroupFetchResult.self) { taskGroup in
            for (baseCode, group) in groups {
                let quotes = group.map(\.quoteCode).sorted().joined(separator: ",")

                taskGroup.addTask { [self] in
                    do {
                        let requestURL = URL(string: "https://api.frankfurter.dev/v2/rates?base=\(baseCode)&quotes=\(quotes)&from=\(from)&to=\(to)&providers=ECB")!
                        let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
                        let response = try JSONDecoder().decode([FrankfurterRateEntry].self, from: data)
                        let entriesByQuote = Dictionary(grouping: response, by: \.quote)
                        var historyByPairID: [String: [TrendPoint]] = [:]
                        var errors: [String] = []

                        for pair in group {
                            guard let entries = entriesByQuote[pair.quoteCode] else {
                                errors.append("Frankfurter 历史接口缺少 \(pair.baseCode)/\(pair.quoteCode)")
                                continue
                            }

                            let points: [TrendPoint] = entries.compactMap { entry -> TrendPoint? in
                                guard let date = SourceDateParser.isoDay(entry.date) else {
                                    return nil
                                }

                                return TrendPoint(timestamp: date, value: entry.rate * Double(pair.baseAmount))
                            }.sorted { lhs, rhs in
                                lhs.timestamp < rhs.timestamp
                            }

                            if points.isEmpty {
                                errors.append("Frankfurter 历史接口未返回 \(pair.baseCode)/\(pair.quoteCode)")
                            } else {
                                historyByPairID[pair.id] = points
                            }
                        }

                        return HistoricalGroupFetchResult(historyByPairID: historyByPairID, errors: errors)
                    } catch {
                        return HistoricalGroupFetchResult(
                            historyByPairID: [:],
                            errors: ["Frankfurter 历史数据刷新失败：\(baseCode)"]
                        )
                    }
                }
            }

            for await result in taskGroup {
                historyByPairID.merge(result.historyByPairID) { current, _ in current }
                errors.append(contentsOf: result.errors)
            }
        }

        return HistoricalFetchResult(historyByPairID: historyByPairID, errors: errors)
    }

    private func fetchTwelveDataSnapshots(for pairs: [CurrencyPair], apiKey: String) async -> ProviderFetchResult {
        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var logs: [DispatchLogEntry] = []
        let refreshedAt = Date()
        var hasFailure = false

        for pair in pairs {
            do {
                var components = URLComponents(string: "https://api.twelvedata.com/exchange_rate")!
                components.queryItems = [
                    URLQueryItem(name: "symbol", value: "\(pair.baseCode)/\(pair.quoteCode)"),
                    URLQueryItem(name: "apikey", value: apiKey)
                ]
                let requestURL = components.url!
                let data = try await responseData(
                    from: requestURL,
                    retryCount: 0,
                    additionalHeaders: ExchangeRateServiceConstants.twelveDataRequestHeaders
                )
                let response = try TwelveDataParser.parseExchangeRate(from: data)

                let effectiveDate = response.timestamp.map(SourceDateParser.isoQueryString(from:))
                snapshots.append(
                    CurrencySnapshot(
                        pair: pair,
                        rate: response.rate * Double(pair.baseAmount),
                        updatedAt: refreshedAt,
                        effectiveDateText: effectiveDate,
                        source: .twelveData,
                        isCached: false
                    )
                )
            } catch {
                hasFailure = true
                let providerError = mapTwelveDataError(error)
                switch providerError {
                case .unsupportedPair:
                    markUnsupported(pair, for: .twelveData)
                    errors.append("Twelve Data 暂不支持 \(pair.compactLabel)")
                    logs.append(DispatchLogEntry(level: .info, message: "Twelve Data 已跳过 \(pair.compactLabel)：该币对不支持"))
                case .rateLimited:
                    beginCooldown(for: .twelveData, duration: ExchangeRateServiceConstants.rateLimitCooldown)
                    errors.append("Twelve Data 已触发限额，转入下一个来源")
                    logs.append(DispatchLogEntry(level: .warning, message: "Twelve Data 触发限额，已切换到下一个来源"))
                    let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: true)
                    return ProviderFetchResult(
                        snapshots: snapshots,
                        errors: errors,
                        sourceStatus: SourceStatus(source: .twelveData, state: state, message: state == .failure ? "Twelve Data 触发限额" : "Twelve Data 部分成功，随后触发限额", timestamp: refreshedAt),
                        logs: logs
                    )
                case .authenticationFailed:
                    beginCooldown(for: .twelveData, duration: ExchangeRateServiceConstants.authenticationCooldown)
                    errors.append("Twelve Data API key 无效或暂不可用，已回退到默认来源")
                    logs.append(DispatchLogEntry(level: .warning, message: "Twelve Data 认证失败，已进入冷却并回退到下一个来源"))
                    let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: true)
                    return ProviderFetchResult(
                        snapshots: snapshots,
                        errors: errors,
                        sourceStatus: SourceStatus(source: .twelveData, state: state, message: state == .failure ? "Twelve Data 认证失败" : "Twelve Data 部分成功，随后认证失败", timestamp: refreshedAt),
                        logs: logs
                    )
                case .noData:
                    errors.append("Twelve Data 未返回 \(pair.compactLabel) 的有效汇率")
                    logs.append(DispatchLogEntry(level: .warning, message: "Twelve Data 未返回 \(pair.compactLabel) 的有效汇率，继续 fallback"))
                case .transport(let message):
                    errors.append("Twelve Data 刷新失败：\(pair.compactLabel)")
                    logs.append(DispatchLogEntry(level: .warning, message: "Twelve Data 刷新失败：\(pair.compactLabel) · \(message)"))
                }
            }
        }

        let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: hasFailure)
        let effectiveDate = snapshots.compactMap(\.effectiveDateText).sorted().last
        let message = providerMessage(for: .twelveData, state: state, effectiveDate: effectiveDate)
        if !snapshots.isEmpty {
            logs.append(DispatchLogEntry(level: .info, message: "Twelve Data 命中 \(snapshots.count) 个货币对"))
        }

        return ProviderFetchResult(
            snapshots: snapshots,
            errors: errors,
            sourceStatus: SourceStatus(source: .twelveData, state: state, message: message, timestamp: refreshedAt),
            logs: logs
        )
    }

    private func fetchExchangeRateAPISnapshots(for pairs: [CurrencyPair], apiKey: String) async -> ProviderFetchResult {
        let refreshedAt = Date()
        let groups = Dictionary(grouping: pairs, by: \.baseCode)
        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var logs: [DispatchLogEntry] = []
        var hadFailure = false
        var effectiveDates: [String] = []

        for (baseCode, group) in groups {
            do {
                let requestURL = URL(string: "https://v6.exchangerate-api.com/v6/\(apiKey)/latest/\(baseCode)")!
                let data = try await responseData(from: requestURL, retryCount: 0)
                let response = try ExchangeRateAPIParser.parseLatest(from: data)
                let effectiveDate = response.timestamp.map(SourceDateParser.isoQueryString(from:))
                if let effectiveDate {
                    effectiveDates.append(effectiveDate)
                }

                for pair in group {
                    guard let quoteRate = response.rate(for: pair.quoteCode), quoteRate > 0 else {
                        markUnsupported(pair, for: .exchangeRateAPI)
                        hadFailure = true
                        errors.append("ExchangeRate-API 缺少 \(pair.compactLabel)")
                        logs.append(DispatchLogEntry(level: .info, message: "ExchangeRate-API 已跳过 \(pair.compactLabel)：返回结果中缺少币种"))
                        continue
                    }

                    snapshots.append(CurrencySnapshot(
                        pair: pair,
                        rate: quoteRate * Double(pair.baseAmount),
                        updatedAt: refreshedAt,
                        effectiveDateText: effectiveDate,
                        source: .exchangeRateAPI,
                        isCached: false
                    ))
                }
            } catch {
                let providerError = mapGenericEnhancedProviderError(error)
                switch providerError {
                case .rateLimited:
                    beginCooldown(for: .exchangeRateAPI, duration: ExchangeRateServiceConstants.rateLimitCooldown)
                    errors.append("ExchangeRate-API 已触发限额，转入下一个来源")
                    logs.append(DispatchLogEntry(level: .warning, message: "ExchangeRate-API 触发限额，已切换到下一个来源"))
                    return providerFailureResult(for: .exchangeRateAPI, snapshots: snapshots, errors: errors, logs: logs, refreshedAt: refreshedAt, attemptedCount: pairs.count, message: "ExchangeRate-API 触发限额")
                case .authenticationFailed:
                    beginCooldown(for: .exchangeRateAPI, duration: ExchangeRateServiceConstants.authenticationCooldown)
                    errors.append("ExchangeRate-API API Key 无效或暂不可用，已回退到下一个来源")
                    logs.append(DispatchLogEntry(level: .warning, message: "ExchangeRate-API 认证失败，已进入冷却并回退到下一个来源"))
                    return providerFailureResult(for: .exchangeRateAPI, snapshots: snapshots, errors: errors, logs: logs, refreshedAt: refreshedAt, attemptedCount: pairs.count, message: "ExchangeRate-API 认证失败")
                case .unsupportedPair:
                    hadFailure = true
                    for pair in group {
                        markUnsupported(pair, for: .exchangeRateAPI)
                    }
                    errors.append("ExchangeRate-API 暂不支持 \(baseCode) 相关货币对")
                    logs.append(DispatchLogEntry(level: .info, message: "ExchangeRate-API 已跳过 \(baseCode)：该基准货币暂不支持"))
                case .noData:
                    hadFailure = true
                    errors.append("ExchangeRate-API 未返回 \(baseCode) 的有效汇率")
                    logs.append(DispatchLogEntry(level: .warning, message: "ExchangeRate-API 未返回 \(baseCode) 的有效汇率，继续 fallback"))
                case .transport(let message):
                    hadFailure = true
                    errors.append("ExchangeRate-API 刷新失败：\(baseCode)")
                    logs.append(DispatchLogEntry(level: .warning, message: "ExchangeRate-API 刷新失败：\(baseCode) · \(message)"))
                }
            }
        }

        let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: hadFailure)
        let message = providerMessage(for: .exchangeRateAPI, state: state, effectiveDate: effectiveDates.sorted().last)
        if !snapshots.isEmpty {
            logs.append(DispatchLogEntry(level: .info, message: "ExchangeRate-API 命中 \(snapshots.count) 个货币对"))
        }

        return ProviderFetchResult(
            snapshots: snapshots,
            errors: errors,
            sourceStatus: SourceStatus(source: .exchangeRateAPI, state: state, message: message, timestamp: refreshedAt),
            logs: logs
        )
    }

    private func fetchOpenExchangeRatesSnapshots(for pairs: [CurrencyPair], appID: String) async -> ProviderFetchResult {
        let refreshedAt = Date()
        let requestedCurrencies = Set(pairs.flatMap { [$0.baseCode, $0.quoteCode] }).sorted()

        do {
            let symbols = requestedCurrencies.joined(separator: ",")
            var components = URLComponents(string: "https://openexchangerates.org/api/latest.json")!
            components.queryItems = [
                URLQueryItem(name: "app_id", value: appID),
                URLQueryItem(name: "symbols", value: symbols),
                URLQueryItem(name: "prettyprint", value: "false")
            ]
            let requestURL = components.url!
            let data = try await responseData(from: requestURL, retryCount: 0)
            let response = try OpenExchangeRatesParser.parseLatest(from: data)
            let effectiveDate = SourceDateParser.isoQueryString(from: response.timestamp)

            var snapshots: [CurrencySnapshot] = []
            var errors: [String] = []
            var logs: [DispatchLogEntry] = []
            var hadFailure = false

            for pair in pairs {
                guard let baseToUSD = response.rate(for: pair.baseCode),
                      let quoteToUSD = response.rate(for: pair.quoteCode),
                      baseToUSD > 0 else {
                    markUnsupported(pair, for: .openExchangeRates)
                    hadFailure = true
                    errors.append("Open Exchange Rates 缺少 \(pair.compactLabel)")
                    logs.append(DispatchLogEntry(level: .info, message: "Open Exchange Rates 已跳过 \(pair.compactLabel)：返回结果中缺少币种"))
                    continue
                }

                let crossRate = (quoteToUSD / baseToUSD) * Double(pair.baseAmount)
                snapshots.append(
                    CurrencySnapshot(
                        pair: pair,
                        rate: crossRate,
                        updatedAt: refreshedAt,
                        effectiveDateText: effectiveDate,
                        source: .openExchangeRates,
                        isCached: false
                    )
                )
            }

            let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: hadFailure)
            let message = providerMessage(for: .openExchangeRates, state: state, effectiveDate: effectiveDate)
            if !snapshots.isEmpty {
                logs.append(DispatchLogEntry(level: .info, message: "Open Exchange Rates 命中 \(snapshots.count) 个货币对"))
            }

            return ProviderFetchResult(
                snapshots: snapshots,
                errors: errors,
                sourceStatus: SourceStatus(source: .openExchangeRates, state: state, message: message, timestamp: refreshedAt),
                logs: logs
            )
        } catch {
            let providerError = mapOpenExchangeRatesError(error)
            switch providerError {
            case .unsupportedPair:
                return ProviderFetchResult(
                    snapshots: [],
                    errors: ["Open Exchange Rates 不支持当前剩余货币对"],
                    sourceStatus: SourceStatus(source: .openExchangeRates, state: .failure, message: "Open Exchange Rates 不支持当前剩余货币对", timestamp: refreshedAt),
                    logs: [
                        DispatchLogEntry(level: .warning, message: "Open Exchange Rates 不支持当前剩余货币对，已回退到下一个来源")
                    ]
                )
            case .rateLimited:
                beginCooldown(for: .openExchangeRates, duration: ExchangeRateServiceConstants.rateLimitCooldown)
                return ProviderFetchResult(
                    snapshots: [],
                    errors: ["Open Exchange Rates 已触发限额，转入下一个来源"],
                    sourceStatus: SourceStatus(source: .openExchangeRates, state: .failure, message: "Open Exchange Rates 触发限额", timestamp: refreshedAt),
                    logs: [
                        DispatchLogEntry(level: .warning, message: "Open Exchange Rates 触发限额，已进入冷却并回退到下一个来源")
                    ]
                )
            case .authenticationFailed:
                beginCooldown(for: .openExchangeRates, duration: ExchangeRateServiceConstants.authenticationCooldown)
                return ProviderFetchResult(
                    snapshots: [],
                    errors: ["Open Exchange Rates App ID 无效或暂不可用，已回退到下一个来源"],
                    sourceStatus: SourceStatus(source: .openExchangeRates, state: .failure, message: "Open Exchange Rates 认证失败", timestamp: refreshedAt),
                    logs: [
                        DispatchLogEntry(level: .warning, message: "Open Exchange Rates 认证失败，已进入冷却并回退到下一个来源")
                    ]
                )
            case .noData:
                return ProviderFetchResult(
                    snapshots: [],
                    errors: ["Open Exchange Rates 未返回有效汇率"],
                    sourceStatus: SourceStatus(source: .openExchangeRates, state: .failure, message: "Open Exchange Rates 未返回有效汇率", timestamp: refreshedAt),
                    logs: [
                        DispatchLogEntry(level: .warning, message: "Open Exchange Rates 未返回有效汇率，已回退到下一个来源")
                    ]
                )
            case .transport(let message):
                return ProviderFetchResult(
                    snapshots: [],
                    errors: ["Open Exchange Rates 刷新失败"],
                    sourceStatus: SourceStatus(source: .openExchangeRates, state: .failure, message: "Open Exchange Rates 刷新失败", timestamp: refreshedAt),
                    logs: [
                        DispatchLogEntry(level: .warning, message: "Open Exchange Rates 刷新失败：\(message)")
                    ]
                )
            }
        }
    }

    private func fetchFixerSnapshots(for pairs: [CurrencyPair], apiKey: String) async -> ProviderFetchResult {
        let refreshedAt = Date()
        let requestedCurrencies = Set(pairs.flatMap { [$0.baseCode, $0.quoteCode] }).sorted()

        do {
            var components = URLComponents(string: "https://data.fixer.io/api/latest")!
            components.queryItems = [
                URLQueryItem(name: "access_key", value: apiKey),
                URLQueryItem(name: "symbols", value: requestedCurrencies.joined(separator: ","))
            ]
            let data = try await responseData(from: components.url!, retryCount: 0)
            let response = try FixerParser.parseLatest(from: data)
            let effectiveDate = response.date ?? response.timestamp.map(SourceDateParser.isoQueryString(from:))

            let result = crossRateSnapshots(
                for: pairs,
                source: .fixer,
                refreshedAt: refreshedAt,
                effectiveDate: effectiveDate,
                missingMessagePrefix: "Fixer",
                rate: { response.rate(for: $0) }
            )
            let state = providerState(resolvedCount: result.snapshots.count, attemptedCount: pairs.count, hadFailure: result.hadFailure)
            let message = providerMessage(for: .fixer, state: state, effectiveDate: effectiveDate)
            var logs = result.logs
            if !result.snapshots.isEmpty {
                logs.append(DispatchLogEntry(level: .info, message: "Fixer 命中 \(result.snapshots.count) 个货币对"))
            }

            return ProviderFetchResult(
                snapshots: result.snapshots,
                errors: result.errors,
                sourceStatus: SourceStatus(source: .fixer, state: state, message: message, timestamp: refreshedAt),
                logs: logs
            )
        } catch {
            return enhancedProviderErrorResult(
                for: .fixer,
                error: error,
                refreshedAt: refreshedAt,
                authenticationMessage: "Fixer API Key 无效或暂不可用，已回退到下一个来源"
            )
        }
    }

    private func fetchCurrencyLayerSnapshots(for pairs: [CurrencyPair], apiKey: String) async -> ProviderFetchResult {
        let refreshedAt = Date()
        let requestedCurrencies = Set(pairs.flatMap { [$0.baseCode, $0.quoteCode] }.filter { $0 != "USD" }).sorted()

        do {
            var components = URLComponents(string: "https://api.currencylayer.com/live")!
            components.queryItems = [
                URLQueryItem(name: "access_key", value: apiKey),
                URLQueryItem(name: "currencies", value: requestedCurrencies.isEmpty ? "EUR" : requestedCurrencies.joined(separator: ","))
            ]
            let data = try await responseData(from: components.url!, retryCount: 0)
            let response = try CurrencyLayerParser.parseLive(from: data)
            let effectiveDate = response.timestamp.map(SourceDateParser.isoQueryString(from:))

            let result = crossRateSnapshots(
                for: pairs,
                source: .currencyLayer,
                refreshedAt: refreshedAt,
                effectiveDate: effectiveDate,
                missingMessagePrefix: "Currencylayer",
                rate: { response.rate(for: $0) }
            )
            let state = providerState(resolvedCount: result.snapshots.count, attemptedCount: pairs.count, hadFailure: result.hadFailure)
            let message = providerMessage(for: .currencyLayer, state: state, effectiveDate: effectiveDate)
            var logs = result.logs
            if !result.snapshots.isEmpty {
                logs.append(DispatchLogEntry(level: .info, message: "Currencylayer 命中 \(result.snapshots.count) 个货币对"))
            }

            return ProviderFetchResult(
                snapshots: result.snapshots,
                errors: result.errors,
                sourceStatus: SourceStatus(source: .currencyLayer, state: state, message: message, timestamp: refreshedAt),
                logs: logs
            )
        } catch {
            return enhancedProviderErrorResult(
                for: .currencyLayer,
                error: error,
                refreshedAt: refreshedAt,
                authenticationMessage: "Currencylayer API Key 无效或暂不可用，已回退到下一个来源"
            )
        }
    }

    private func fetchCBRResult(for pairs: [CurrencyPair]) async -> ExchangeFetchResult {
        do {
            let requestURL = URL(string: "https://www.cbr.ru/scripts/XML_daily.asp")!
            let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
            let document = try CBRDailyParser.parseDocument(from: data)
            let refreshedAt = Date()
            var snapshots: [CurrencySnapshot] = []

            for pair in pairs {
                guard let rubPerUnit = document.ratesByCode[pair.baseCode] else {
                    continue
                }

                snapshots.append(
                    CurrencySnapshot(
                        pair: pair,
                        rate: rubPerUnit * Double(pair.baseAmount),
                        updatedAt: refreshedAt,
                        effectiveDateText: document.effectiveDate,
                        source: .cbr,
                        isCached: false
                    )
                )
            }

            let missingPairs = pairs.filter { pair in
                document.ratesByCode[pair.baseCode] == nil
            }

            let errors = missingPairs.isEmpty
                ? []
                : ["CBR 缺少 \(missingPairs.map { "\($0.baseCode)/\($0.quoteCode)" }.joined(separator: "、"))"]

            let state: SourceStatus.State
            if missingPairs.isEmpty {
                state = .success
            } else if snapshots.isEmpty {
                state = .failure
            } else {
                state = .partial
            }

            let message = document.effectiveDate.map {
                switch state {
                case .success:
                    "CBR 数据日 \($0)"
                case .partial:
                    "CBR 部分成功 · \($0)"
                case .failure:
                    "CBR 数据缺失 · \($0)"
                case .idle:
                    "当前未使用 CBR"
                }
            } ?? {
                switch state {
                case .success:
                    "CBR 数据可用"
                case .partial:
                    "CBR 部分成功"
                case .failure:
                    "CBR 数据缺失"
                case .idle:
                    "当前未使用 CBR"
                }
            }()

            return ExchangeFetchResult(
                snapshots: snapshots,
                errors: errors,
                sourceStatuses: [
                    SourceStatus(source: .cbr, state: state, message: message, timestamp: refreshedAt)
                ],
                logs: [
                    DispatchLogEntry(level: missingPairs.isEmpty ? .info : .warning, message: missingPairs.isEmpty ? "CBR 命中 \(snapshots.count) 个 RUB 货币对" : "CBR 仅命中 \(snapshots.count) 个 RUB 货币对")
                ]
            )
        } catch {
            return ExchangeFetchResult(
                snapshots: [],
                errors: ["CBR 刷新失败"],
                sourceStatuses: [
                    SourceStatus(source: .cbr, state: .failure, message: "CBR 刷新失败", timestamp: .now)
                ],
                logs: [
                    DispatchLogEntry(level: .warning, message: "CBR 刷新失败，已准备回退到缓存")
                ]
            )
        }
    }

    private func fetchECBSnapshots(for pairs: [CurrencyPair]) async -> ProviderFetchResult {
        let refreshedAt = Date()
        let requestedCurrencies = Set(pairs.flatMap { [$0.baseCode, $0.quoteCode] }.filter { $0 != "EUR" }).sorted()

        guard !requestedCurrencies.isEmpty else {
            return ProviderFetchResult(
                snapshots: [],
                errors: ["ECB 直连缺少可查询币种"],
                sourceStatus: SourceStatus(source: .ecb, state: .failure, message: "ECB 直连缺少可查询币种", timestamp: refreshedAt),
                logs: [
                    DispatchLogEntry(level: .warning, message: "ECB Direct 缺少可查询币种，准备继续回退")
                ]
            )
        }

        do {
            let requestURL = URL(string: "https://data-api.ecb.europa.eu/service/data/EXR/D.\(requestedCurrencies.joined(separator: "+")).EUR.SP00.A?lastNObservations=5&format=jsondata&detail=dataonly")!
            let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
            let seriesByCurrency = try ECBEXRParser.parseSeriesByCurrency(from: data)
            var snapshots: [CurrencySnapshot] = []
            var missingPairs: [CurrencyPair] = []

            for pair in pairs {
                guard let latestPoint = crossSeries(for: pair, using: seriesByCurrency).last else {
                    missingPairs.append(pair)
                    continue
                }

                snapshots.append(
                    CurrencySnapshot(
                        pair: pair,
                        rate: latestPoint.value,
                        updatedAt: refreshedAt,
                        effectiveDateText: SourceDateParser.isoQueryString(from: latestPoint.timestamp),
                        source: .ecb,
                        isCached: false
                    )
                )
            }

            let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count)
            let errors = missingPairs.isEmpty ? [] : ["ECB 直连缺少 \(missingPairs.map(\.compactLabel).joined(separator: "、"))"]
            let effectiveDate = snapshots.compactMap(\.effectiveDateText).sorted().last
            let message = providerMessage(for: .ecb, state: state, effectiveDate: effectiveDate)

            return ProviderFetchResult(
                snapshots: snapshots,
                errors: errors,
                sourceStatus: SourceStatus(source: .ecb, state: state, message: message, timestamp: refreshedAt),
                logs: [
                    DispatchLogEntry(level: snapshots.isEmpty ? .warning : .info, message: snapshots.isEmpty ? "ECB Direct 未命中当前剩余货币对" : "ECB Direct 命中 \(snapshots.count) 个货币对")
                ]
            )
        } catch {
            return ProviderFetchResult(
                snapshots: [],
                errors: ["ECB 直连刷新失败"],
                sourceStatus: SourceStatus(source: .ecb, state: .failure, message: "ECB 直连刷新失败", timestamp: refreshedAt),
                logs: [
                    DispatchLogEntry(level: .warning, message: "ECB Direct 刷新失败，继续回退到 Frankfurter")
                ]
            )
        }
    }

    private func fetchFrankfurterSnapshots(for pairs: [CurrencyPair]) async -> ProviderFetchResult {
        let groups = Dictionary(grouping: pairs, by: \.baseCode)
        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var hadFailure = false
        var responseDates: Set<String> = []
        let refreshedAt = Date()

        await withTaskGroup(of: SnapshotGroupFetchResult.self) { taskGroup in
            for (baseCode, group) in groups {
                let quotes = group.map(\.quoteCode).sorted().joined(separator: ",")

                taskGroup.addTask { [self] in
                    do {
                        let requestURL = URL(string: "https://api.frankfurter.dev/v2/rates?base=\(baseCode)&quotes=\(quotes)&providers=ECB")!
                        let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
                        let response = try JSONDecoder().decode([FrankfurterRateEntry].self, from: data)
                        let ratesByQuote = Dictionary(uniqueKeysWithValues: response.map { ($0.quote, $0) })

                        let snapshots = group.compactMap { pair -> CurrencySnapshot? in
                            guard let entry = ratesByQuote[pair.quoteCode] else {
                                return nil
                            }

                            return CurrencySnapshot(
                                pair: pair,
                                rate: entry.rate * Double(pair.baseAmount),
                                updatedAt: refreshedAt,
                                effectiveDateText: entry.date,
                                source: .frankfurter,
                                isCached: false
                            )
                        }

                        let missingQuotes = group.filter { ratesByQuote[$0.quoteCode] == nil }
                        return SnapshotGroupFetchResult(
                            snapshots: snapshots,
                            errors: missingQuotes.isEmpty ? [] : ["Frankfurter 缺少 \(missingQuotes.map(\.compactLabel).joined(separator: "、"))"],
                            responseDates: Set(response.map(\.date)),
                            hadFailure: !missingQuotes.isEmpty
                        )
                    } catch {
                        return SnapshotGroupFetchResult(
                            snapshots: [],
                            errors: ["Frankfurter 刷新失败：\(baseCode)"],
                            responseDates: [],
                            hadFailure: true
                        )
                    }
                }
            }

            for await result in taskGroup {
                snapshots.append(contentsOf: result.snapshots)
                errors.append(contentsOf: result.errors)
                responseDates.formUnion(result.responseDates)
                hadFailure = hadFailure || result.hadFailure
            }
        }

        let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: hadFailure)
        let message = providerMessage(for: .frankfurter, state: state, effectiveDate: responseDates.sorted().last)

        return ProviderFetchResult(
            snapshots: snapshots,
            errors: errors,
            sourceStatus: SourceStatus(source: .frankfurter, state: state, message: message, timestamp: refreshedAt),
            logs: [
                DispatchLogEntry(level: snapshots.isEmpty ? .warning : .info, message: snapshots.isEmpty ? "Frankfurter 未命中当前剩余货币对" : "Frankfurter 命中 \(snapshots.count) 个货币对")
            ]
        )
    }

    private func fetchFloatRatesSnapshots(for pairs: [CurrencyPair]) async -> ProviderFetchResult {
        let groups = Dictionary(grouping: pairs, by: \.baseCode)
        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var hadFailure = false
        var responseDates: Set<String> = []
        let refreshedAt = Date()

        await withTaskGroup(of: SnapshotGroupFetchResult.self) { taskGroup in
            for (baseCode, group) in groups {
                taskGroup.addTask { [self] in
                    do {
                        let requestURL = URL(string: "https://www.floatrates.com/daily/\(baseCode.lowercased()).json")!
                        let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
                        let response = try JSONDecoder().decode([String: FloatRatesEntry].self, from: data)
                        var responseDates: Set<String> = []

                        let snapshots = group.compactMap { pair -> CurrencySnapshot? in
                            guard let entry = response[pair.quoteCode.lowercased()] else {
                                return nil
                            }

                            let effectiveDate = SourceDateParser.httpDay(entry.date).map(SourceDateParser.isoQueryString(from:))
                            if let effectiveDate {
                                responseDates.insert(effectiveDate)
                            }

                            return CurrencySnapshot(
                                pair: pair,
                                rate: entry.rate * Double(pair.baseAmount),
                                updatedAt: refreshedAt,
                                effectiveDateText: effectiveDate,
                                source: .floatRates,
                                isCached: false
                            )
                        }

                        let missingQuotes = group.filter { response[$0.quoteCode.lowercased()] == nil }
                        return SnapshotGroupFetchResult(
                            snapshots: snapshots,
                            errors: missingQuotes.isEmpty ? [] : ["FloatRates 缺少 \(missingQuotes.map(\.compactLabel).joined(separator: "、"))"],
                            responseDates: responseDates,
                            hadFailure: !missingQuotes.isEmpty
                        )
                    } catch {
                        return SnapshotGroupFetchResult(
                            snapshots: [],
                            errors: ["FloatRates 刷新失败：\(baseCode)"],
                            responseDates: [],
                            hadFailure: true
                        )
                    }
                }
            }

            for await result in taskGroup {
                snapshots.append(contentsOf: result.snapshots)
                errors.append(contentsOf: result.errors)
                responseDates.formUnion(result.responseDates)
                hadFailure = hadFailure || result.hadFailure
            }
        }

        let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: hadFailure)
        let message = providerMessage(for: .floatRates, state: state, effectiveDate: responseDates.sorted().last)

        return ProviderFetchResult(
            snapshots: snapshots,
            errors: errors,
            sourceStatus: SourceStatus(source: .floatRates, state: state, message: message, timestamp: refreshedAt),
            logs: [
                DispatchLogEntry(level: snapshots.isEmpty ? .warning : .info, message: snapshots.isEmpty ? "FloatRates 未命中当前剩余货币对" : "FloatRates 命中 \(snapshots.count) 个货币对")
            ]
        )
    }

    private func fetchCurrencyAPISnapshots(for pairs: [CurrencyPair]) async -> ProviderFetchResult {
        let groups = Dictionary(grouping: pairs, by: \.baseCode)
        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var hadFailure = false
        var responseDates: Set<String> = []
        let refreshedAt = Date()

        await withTaskGroup(of: SnapshotGroupFetchResult.self) { taskGroup in
            for (baseCode, group) in groups {
                taskGroup.addTask { [self] in
                    do {
                        let requestURL = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(baseCode.lowercased()).json")!
                        let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
                        let response = try CurrencyAPIParser.parseRates(from: data, expectedBaseCode: baseCode.lowercased())

                        let snapshots = group.compactMap { pair -> CurrencySnapshot? in
                            guard let rate = response.rates[pair.quoteCode.lowercased()] else {
                                return nil
                            }

                            return CurrencySnapshot(
                                pair: pair,
                                rate: rate * Double(pair.baseAmount),
                                updatedAt: refreshedAt,
                                effectiveDateText: response.date.isEmpty ? nil : response.date,
                                source: .currencyAPI,
                                isCached: false
                            )
                        }

                        let missingQuotes = group.filter { response.rates[$0.quoteCode.lowercased()] == nil }
                        return SnapshotGroupFetchResult(
                            snapshots: snapshots,
                            errors: missingQuotes.isEmpty ? [] : ["Currency API 缺少 \(missingQuotes.map(\.compactLabel).joined(separator: "、"))"],
                            responseDates: response.date.isEmpty ? [] : [response.date],
                            hadFailure: !missingQuotes.isEmpty
                        )
                    } catch {
                        return SnapshotGroupFetchResult(
                            snapshots: [],
                            errors: ["Currency API 刷新失败：\(baseCode)"],
                            responseDates: [],
                            hadFailure: true
                        )
                    }
                }
            }

            for await result in taskGroup {
                snapshots.append(contentsOf: result.snapshots)
                errors.append(contentsOf: result.errors)
                responseDates.formUnion(result.responseDates)
                hadFailure = hadFailure || result.hadFailure
            }
        }

        let state = providerState(resolvedCount: snapshots.count, attemptedCount: pairs.count, hadFailure: hadFailure)
        let message = providerMessage(for: .currencyAPI, state: state, effectiveDate: responseDates.sorted().last)

        return ProviderFetchResult(
            snapshots: snapshots,
            errors: errors,
            sourceStatus: SourceStatus(source: .currencyAPI, state: state, message: message, timestamp: refreshedAt),
            logs: [
                DispatchLogEntry(level: snapshots.isEmpty ? .warning : .info, message: snapshots.isEmpty ? "Currency API 未命中当前剩余货币对" : "Currency API 命中 \(snapshots.count) 个货币对")
            ]
        )
    }

    private func crossSeries(for pair: CurrencyPair, using seriesByCurrency: [String: [TrendPoint]]) -> [TrendPoint] {
        let baseByDay = pair.baseCode == "EUR" ? [:] : pointsByDay(for: seriesByCurrency[pair.baseCode] ?? [])
        let quoteByDay = pair.quoteCode == "EUR" ? [:] : pointsByDay(for: seriesByCurrency[pair.quoteCode] ?? [])

        let dayKeys: [String]
        if pair.baseCode == "EUR" {
            dayKeys = quoteByDay.keys.sorted()
        } else if pair.quoteCode == "EUR" {
            dayKeys = baseByDay.keys.sorted()
        } else {
            dayKeys = Set(baseByDay.keys).intersection(quoteByDay.keys).sorted()
        }

        return dayKeys.compactMap { dayKey in
            let basePerEuro = pair.baseCode == "EUR" ? 1.0 : baseByDay[dayKey]
            let quotePerEuro = pair.quoteCode == "EUR" ? 1.0 : quoteByDay[dayKey]

            guard let basePerEuro, let quotePerEuro, basePerEuro > 0,
                  let timestamp = SourceDateParser.isoDay(dayKey) else {
                return nil
            }

            return TrendPoint(timestamp: timestamp, value: (quotePerEuro / basePerEuro) * Double(pair.baseAmount))
        }
    }

    private func pointsByDay(for points: [TrendPoint]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: points.map { (SourceDateParser.isoQueryString(from: $0.timestamp), $0.value) })
    }

    private func crossRateSnapshots(
        for pairs: [CurrencyPair],
        source: ExchangeSource,
        refreshedAt: Date,
        effectiveDate: String?,
        missingMessagePrefix: String,
        rate: (String) -> Double?
    ) -> (snapshots: [CurrencySnapshot], errors: [String], logs: [DispatchLogEntry], hadFailure: Bool) {
        var snapshots: [CurrencySnapshot] = []
        var errors: [String] = []
        var logs: [DispatchLogEntry] = []
        var hadFailure = false

        for pair in pairs {
            guard let baseRate = rate(pair.baseCode),
                  let quoteRate = rate(pair.quoteCode),
                  baseRate > 0 else {
                markUnsupported(pair, for: source)
                hadFailure = true
                errors.append("\(missingMessagePrefix) 缺少 \(pair.compactLabel)")
                logs.append(DispatchLogEntry(level: .info, message: "\(missingMessagePrefix) 已跳过 \(pair.compactLabel)：返回结果中缺少币种"))
                continue
            }

            snapshots.append(CurrencySnapshot(
                pair: pair,
                rate: (quoteRate / baseRate) * Double(pair.baseAmount),
                updatedAt: refreshedAt,
                effectiveDateText: effectiveDate,
                source: source,
                isCached: false
            ))
        }

        return (snapshots, errors, logs, hadFailure)
    }

    private func providerFailureResult(
        for source: ExchangeSource,
        snapshots: [CurrencySnapshot],
        errors: [String],
        logs: [DispatchLogEntry],
        refreshedAt: Date,
        attemptedCount: Int,
        message: String
    ) -> ProviderFetchResult {
        let state = providerState(resolvedCount: snapshots.count, attemptedCount: attemptedCount, hadFailure: true)
        return ProviderFetchResult(
            snapshots: snapshots,
            errors: errors,
            sourceStatus: SourceStatus(source: source, state: state, message: state == .failure ? message : "\(source.displayName) 部分成功，随后失败", timestamp: refreshedAt),
            logs: logs
        )
    }

    private func enhancedProviderErrorResult(
        for source: ExchangeSource,
        error: Error,
        refreshedAt: Date,
        authenticationMessage: String
    ) -> ProviderFetchResult {
        let providerError = mapGenericEnhancedProviderError(error)
        switch providerError {
        case .unsupportedPair:
            return ProviderFetchResult(
                snapshots: [],
                errors: ["\(source.displayName) 不支持当前剩余货币对"],
                sourceStatus: SourceStatus(source: source, state: .failure, message: "\(source.displayName) 不支持当前剩余货币对", timestamp: refreshedAt),
                logs: [DispatchLogEntry(level: .warning, message: "\(source.displayName) 不支持当前剩余货币对，已回退到下一个来源")]
            )
        case .rateLimited:
            beginCooldown(for: source, duration: ExchangeRateServiceConstants.rateLimitCooldown)
            return ProviderFetchResult(
                snapshots: [],
                errors: ["\(source.displayName) 已触发限额，转入下一个来源"],
                sourceStatus: SourceStatus(source: source, state: .failure, message: "\(source.displayName) 触发限额", timestamp: refreshedAt),
                logs: [DispatchLogEntry(level: .warning, message: "\(source.displayName) 触发限额，已进入冷却并回退到下一个来源")]
            )
        case .authenticationFailed:
            beginCooldown(for: source, duration: ExchangeRateServiceConstants.authenticationCooldown)
            return ProviderFetchResult(
                snapshots: [],
                errors: [authenticationMessage],
                sourceStatus: SourceStatus(source: source, state: .failure, message: "\(source.displayName) 认证失败", timestamp: refreshedAt),
                logs: [DispatchLogEntry(level: .warning, message: "\(source.displayName) 认证失败，已进入冷却并回退到下一个来源")]
            )
        case .noData:
            return ProviderFetchResult(
                snapshots: [],
                errors: ["\(source.displayName) 未返回有效汇率"],
                sourceStatus: SourceStatus(source: source, state: .failure, message: "\(source.displayName) 未返回有效汇率", timestamp: refreshedAt),
                logs: [DispatchLogEntry(level: .warning, message: "\(source.displayName) 未返回有效汇率，已回退到下一个来源")]
            )
        case .transport(let message):
            return ProviderFetchResult(
                snapshots: [],
                errors: ["\(source.displayName) 刷新失败"],
                sourceStatus: SourceStatus(source: source, state: .failure, message: "\(source.displayName) 刷新失败", timestamp: refreshedAt),
                logs: [DispatchLogEntry(level: .warning, message: "\(source.displayName) 刷新失败：\(message)")]
            )
        }
    }

    private func providerState(resolvedCount: Int, attemptedCount: Int, hadFailure: Bool = false) -> SourceStatus.State {
        if resolvedCount == 0 {
            return attemptedCount == 0 ? .idle : .failure
        }

        if resolvedCount < attemptedCount || hadFailure {
            return .partial
        }

        return .success
    }

    private func providerMessage(for source: ExchangeSource, state: SourceStatus.State, effectiveDate: String?) -> String {
        let sourceName = source.displayName

        switch state {
        case .success:
            return effectiveDate.map { "\(sourceName) 数据日 \($0)" } ?? "\(sourceName) 数据可用"
        case .partial:
            return effectiveDate.map { "\(sourceName) 部分成功 · \($0)" } ?? "\(sourceName) 部分成功"
        case .failure:
            return "\(sourceName) 刷新失败"
        case .idle:
            return "当前未使用 \(sourceName)"
        }
    }

    private func cbrCurrencyReference() async throws -> [String: String] {
        if let cbrCurrencyIDByCode {
            return cbrCurrencyIDByCode
        }

        let requestURL = URL(string: "https://www.cbr.ru/scripts/XML_valFull.asp")!
        let data = try await responseData(from: requestURL, timeoutInterval: ExchangeRateServiceConstants.fallbackTimeout)
        let mapping = try CBRCurrencyReferenceParser.parseCurrencyIDs(from: data)
        cbrCurrencyIDByCode = mapping
        return mapping
    }

    private func historicalRequestRange() -> (start: Date, end: Date) {
        let end = Date()
        let start = end.addingTimeInterval(-Double(ExchangeRateServiceConstants.historicalLookbackDays) * 24 * 3600)
        return (start, end)
    }

    private func mapTwelveDataError(_ error: Error) -> EnhancedProviderError {
        if let providerError = error as? EnhancedProviderError {
            switch providerError {
            case .transport(let message):
                let lowercased = message.lowercased()
                if lowercased.contains("limit") || lowercased.contains("quota") || lowercased.contains("credits") {
                    return .rateLimited
                }
                if lowercased.contains("not found")
                    || lowercased.contains("not support")
                    || lowercased.contains("not available")
                    || lowercased.contains("invalid symbol")
                    || (lowercased.contains("symbol") && lowercased.contains("invalid")) {
                    return .unsupportedPair
                }
                if lowercased.contains("api key") || lowercased.contains("apikey") || lowercased.contains("unauthorized") || lowercased.contains("invalid") {
                    return .authenticationFailed
                }
                return .transport(message)
            default:
                return providerError
            }
        }

        if let httpError = error as? HTTPStatusError {
            let message = providerErrorMessage(from: httpError.body).lowercased()
            if message.contains("quota") || message.contains("credits") || message.contains("limit") {
                return .rateLimited
            }
            if message.contains("not support")
                || message.contains("not found")
                || message.contains("not available")
                || message.contains("invalid symbol")
                || (message.contains("symbol") && message.contains("invalid")) {
                return .unsupportedPair
            }
            if message.contains("invalid") || message.contains("api key") || message.contains("apikey") {
                return .authenticationFailed
            }
            if httpError.statusCode == 401 || httpError.statusCode == 403 {
                return .authenticationFailed
            }
            if httpError.statusCode == 404 {
                return .unsupportedPair
            }
            if httpError.statusCode == 429 {
                return .rateLimited
            }
            return .transport("HTTP \(httpError.statusCode)")
        }

        if let urlError = error as? URLError {
            return .transport(urlError.localizedDescription)
        }

        return .transport(error.localizedDescription)
    }

    private func providerErrorMessage(from body: String?) -> String {
        guard let body else {
            return ""
        }

        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return body
        }

        return message
    }

    private func mapGenericEnhancedProviderError(_ error: Error) -> EnhancedProviderError {
        if let providerError = error as? EnhancedProviderError {
            switch providerError {
            case .transport(let message):
                let lowercased = message.lowercased()
                if lowercased.contains("quota")
                    || lowercased.contains("credits")
                    || lowercased.contains("limit")
                    || lowercased.contains("usage")
                    || lowercased.contains("too many") {
                    return .rateLimited
                }
                if lowercased.contains("unsupported")
                    || lowercased.contains("not supported")
                    || lowercased.contains("unsupported-code")
                    || lowercased.contains("invalid base")
                    || lowercased.contains("invalid currency") {
                    return .unsupportedPair
                }
                if lowercased.contains("invalid")
                    || lowercased.contains("api key")
                    || lowercased.contains("access key")
                    || lowercased.contains("inactive-account")
                    || lowercased.contains("malformed-request")
                    || lowercased.contains("not allowed")
                    || lowercased.contains("unauthorized") {
                    return .authenticationFailed
                }
                return .transport(message)
            default:
                return providerError
            }
        }

        if let httpError = error as? HTTPStatusError {
            let message = providerErrorMessage(from: httpError.body).lowercased()
            if message.contains("quota") || message.contains("limit") || message.contains("credits") {
                return .rateLimited
            }
            if message.contains("unsupported") || message.contains("not supported") || message.contains("not found") {
                return .unsupportedPair
            }
            if message.contains("invalid") || message.contains("api key") || message.contains("access key") {
                return .authenticationFailed
            }
            if httpError.statusCode == 401 || httpError.statusCode == 403 {
                return .authenticationFailed
            }
            if httpError.statusCode == 404 {
                return .unsupportedPair
            }
            if httpError.statusCode == 429 {
                return .rateLimited
            }
            return .transport("HTTP \(httpError.statusCode)")
        }

        if let urlError = error as? URLError {
            return .transport(urlError.localizedDescription)
        }

        return .transport(error.localizedDescription)
    }

    private func mapOpenExchangeRatesError(_ error: Error) -> EnhancedProviderError {
        if let providerError = error as? EnhancedProviderError {
            switch providerError {
            case .transport(let message):
                let lowercased = message.lowercased()
                if lowercased.contains("app id") || lowercased.contains("invalid_app_id") || lowercased.contains("not allowed") || lowercased.contains("unauthorized") {
                    return .authenticationFailed
                }
                if lowercased.contains("limit") || lowercased.contains("quota") || lowercased.contains("too many") {
                    return .rateLimited
                }
                return .transport(message)
            default:
                return providerError
            }
        }

        if let httpError = error as? HTTPStatusError {
            if httpError.statusCode == 401 || httpError.statusCode == 403 {
                return .authenticationFailed
            }
            if httpError.statusCode == 429 {
                return .rateLimited
            }
            let body = httpError.body?.lowercased() ?? ""
            if body.contains("invalid_app_id") || body.contains("app id") || body.contains("unauthorized") {
                return .authenticationFailed
            }
            if body.contains("quota") || body.contains("limit") || body.contains("too many") {
                return .rateLimited
            }
            return .transport("HTTP \(httpError.statusCode)")
        }

        if let urlError = error as? URLError {
            return .transport(urlError.localizedDescription)
        }

        return .transport(error.localizedDescription)
    }

    private func responseData(
        from url: URL,
        retryCount: Int = 1,
        timeoutInterval: TimeInterval = ExchangeRateServiceConstants.standardTimeout,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else {
            throw URLError(.secureConnectionFailed)
        }

        var currentAttempt = 0

        while true {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeoutInterval
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.httpShouldHandleCookies = false
                request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
                request.setValue("CurrencyTracker/1.0", forHTTPHeaderField: "User-Agent")
                for (field, value) in additionalHeaders {
                    request.setValue(value, forHTTPHeaderField: field)
                }

                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let body = String(data: data, encoding: .utf8)
                    throw HTTPStatusError(statusCode: httpResponse.statusCode, body: body)
                }

                return data
            } catch {
                guard currentAttempt < retryCount, shouldRetry(after: error) else {
                    throw error
                }

                currentAttempt += 1
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private func shouldRetry(after error: Error) -> Bool {
        if let httpError = error as? HTTPStatusError {
            return httpError.statusCode == 429 || (500...599).contains(httpError.statusCode)
        }

        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut,
             .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

}
