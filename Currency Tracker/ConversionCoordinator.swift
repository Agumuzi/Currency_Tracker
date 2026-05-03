//
//  ConversionCoordinator.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

protocol ExchangeSnapshotFetching: Sendable {
    func fetchSnapshots(
        for pairs: [CurrencyPair],
        configuration: EnhancedSourceConfiguration
    ) async -> ExchangeFetchResult
}

protocol ExchangeStateStoring: Sendable {
    func load() async -> CachedExchangeState?
    func save(_ state: CachedExchangeState) async
}

extension ExchangeRateService: ExchangeSnapshotFetching {}
extension ExchangeRateStore: ExchangeStateStoring {}

enum TextConversionEntrySource: String, Sendable {
    case services
    case globalShortcut

    var logLabel: String {
        switch self {
        case .services:
            "Services"
        case .globalShortcut:
            "全局快捷键"
        }
    }
}

@MainActor
final class ConversionCoordinator {
    private let preferences: PreferencesStore
    private let credentialStore: EnhancedSourceCredentialStore
    private let service: any ExchangeSnapshotFetching
    private let store: any ExchangeStateStoring
    private let promptPanel: any LightweightPromptPaneling
    private let clipboardWriter: any ClipboardWriting
    private let liveLogHandler: @MainActor (RefreshLogEntry.Level, String) -> Void
    private let snapshotMergeHandler: @MainActor ([CurrencySnapshot]) -> Void

    init(
        preferences: PreferencesStore,
        credentialStore: EnhancedSourceCredentialStore,
        service: any ExchangeSnapshotFetching,
        store: any ExchangeStateStoring,
        promptPanel: any LightweightPromptPaneling,
        clipboardWriter: any ClipboardWriting,
        liveLogHandler: @escaping @MainActor (RefreshLogEntry.Level, String) -> Void,
        snapshotMergeHandler: @escaping @MainActor ([CurrencySnapshot]) -> Void = { _ in }
    ) {
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.service = service
        self.store = store
        self.promptPanel = promptPanel
        self.clipboardWriter = clipboardWriter
        self.liveLogHandler = liveLogHandler
        self.snapshotMergeHandler = snapshotMergeHandler
    }

    func handleSelectedText(
        _ selectedText: String,
        source: TextConversionEntrySource = .services
    ) async {
        var operationLogs: [RefreshLogEntry] = []
        var snapshotsToPersist: [CurrencySnapshot] = []

        func log(_ level: RefreshLogEntry.Level, _ message: String) {
            let entry = RefreshLogEntry(timestamp: .now, level: level, message: message)
            operationLogs.append(entry)
            liveLogHandler(level, message)
        }

        let trimmedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        log(.info, "入口来源：\(source.logLabel)")
        log(.info, "收到的选中文本（已脱敏）：\(redactedInputSummary(trimmedText))")

        guard let parsedAmount = MoneyParsing.parse(trimmedText) else {
            log(.warning, "金额解析失败，无法识别可换算金额")
            await promptPanel.showError(
                title: "无法识别金额",
                message: "请重新选择包含金额的文本，例如 1234 USD、€299、599.99 土耳其里拉 或 1,234.56。"
            )
            await persistOperationArtifacts(logs: operationLogs, snapshots: snapshotsToPersist)
            return
        }

        let sourceAmount: Decimal
        switch parsedAmount.amount {
        case .resolved(let amount):
            sourceAmount = amount
            log(.info, "解析出的金额：\(ServiceConversionFormatting.sourceAmount(amount))")
        case .ambiguous(let rawText, let options):
            log(.info, "检测到数值格式歧义，准备弹出确认面板")
            guard let confirmedAmount = await promptPanel.chooseAmountInterpretation(
                rawText: rawText,
                options: options
            ) else {
                log(.warning, "用户取消了数值解释确认")
                await persistOperationArtifacts(logs: operationLogs, snapshots: snapshotsToPersist)
                return
            }

            sourceAmount = confirmedAmount
            log(.info, "用户确认后的金额：\(ServiceConversionFormatting.sourceAmount(sourceAmount))")
        }

        let sourceCurrencyCode: String?
        switch parsedAmount.currency {
        case .explicit(let code):
            log(.info, "已识别原始货币：\(code)")
            sourceCurrencyCode = code
        case .ambiguous(let symbol, let candidates):
            log(.info, "是否识别出原始货币：否（符号歧义：\(symbol)）")
            log(.info, "是否触发歧义选择面板：是")
            sourceCurrencyCode = await promptPanel.chooseCurrencyForAmbiguousSymbol(
                amount: sourceAmount,
                symbol: symbol,
                candidates: candidates,
                targetCurrencyCode: preferences.baseCurrencyCode
            )
        case .missing:
            log(.info, "是否识别出原始货币：否（纯数字）")
            log(.info, "是否触发纯数字输入面板：是")
            sourceCurrencyCode = await promptPanel.chooseCurrencyForManualInput(
                amount: sourceAmount,
                targetCurrencyCode: preferences.baseCurrencyCode
            )
        }

        guard let sourceCurrencyCode else {
            log(.warning, "用户取消了本次换算")
            await persistOperationArtifacts(logs: operationLogs, snapshots: snapshotsToPersist)
            return
        }

        let targetCurrencyCode = preferences.baseCurrencyCode
        let resolvedRate = await resolveRate(
            from: sourceCurrencyCode,
            to: targetCurrencyCode,
            log: log,
            snapshotsToPersist: &snapshotsToPersist
        )

        guard let resolvedRate else {
            log(.error, "换算失败：没有拿到可用汇率")
            await promptPanel.showError(
                title: "当前无法换算",
                message: "没有拿到可用汇率，请稍后再试。"
            )
            await persistOperationArtifacts(logs: operationLogs, snapshots: snapshotsToPersist)
            return
        }

        let resultAmount = decimalValue(
            NSDecimalNumber(decimal: sourceAmount)
                .multiplying(by: NSDecimalNumber(value: resolvedRate))
        )

        let presentation = ConversionPresentation(
            sourceAmount: sourceAmount,
            sourceCurrencyCode: sourceCurrencyCode,
            targetAmount: resultAmount,
            targetCurrencyCode: targetCurrencyCode,
            fractionDigits: preferences.conversionFractionDigits
        )

        log(.info, "换算完成，结果已生成")
        let didWriteClipboard = clipboardWriter.write(presentation.clipboardText)
        log(
            didWriteClipboard ? .info : .warning,
            didWriteClipboard ? "换算结果已写入剪贴板" : "写入剪贴板失败"
        )

        let didShowPopup = await promptPanel.showResult(presentation)
        log(
            didShowPopup ? .info : .warning,
            didShowPopup ? "弹窗显示成功" : "弹窗显示失败"
        )

        await persistOperationArtifacts(logs: operationLogs, snapshots: snapshotsToPersist)
    }

    private func resolveRate(
        from sourceCurrencyCode: String,
        to targetCurrencyCode: String,
        log: (RefreshLogEntry.Level, String) -> Void,
        snapshotsToPersist: inout [CurrencySnapshot]
    ) async -> Double? {
        if sourceCurrencyCode == targetCurrencyCode {
            log(.info, "原始货币与基准货币一致，直接按 1:1 输出")
            return 1
        }

        guard let plan = ConversionRatePlan.make(sourceCurrencyCode: sourceCurrencyCode, targetCurrencyCode: targetCurrencyCode) else {
            log(.error, "当前不支持 \(sourceCurrencyCode) → \(targetCurrencyCode) 的换算路径")
            return nil
        }

        let cachedState = await store.load() ?? .empty
        let cachedSnapshot = cachedState.snapshots.first(where: { $0.id == plan.fetchPair.id })
        let refreshDecision = RefreshPolicy.shouldRefreshServiceConversion(lastSuccessfulUpdateAt: cachedSnapshot?.updatedAt)

        switch refreshDecision {
        case .useCache:
            if let cachedSnapshot {
                log(.info, "是否使用缓存：是（直接使用 1 小时内缓存：\(plan.displayLabel)）")
                return plan.effectiveRate(from: cachedSnapshot)
            }
        case .refreshSilently:
            log(.info, "是否使用缓存：是（存在旧缓存，可在静默刷新失败时回退）")
            log(.info, "是否因缓存超过 1 小时而尝试静默刷新：是")
            if cachedSnapshot == nil {
                log(.info, "缓存中缺少所需汇率，开始静默刷新：\(plan.displayLabel)")
            } else {
                log(.info, "缓存已超过 1 小时，开始静默刷新：\(plan.displayLabel)")
            }
        }

        let result = await service.fetchSnapshots(
            for: [plan.fetchPair],
            configuration: credentialStore.configuration
        )

        for serviceLog in result.logs {
            log(serviceLog.level, "文本换算·\(serviceLog.message)")
        }

        if let refreshedSnapshot = result.snapshots.first(where: { $0.id == plan.fetchPair.id }) {
            log(.info, "静默刷新是否成功：是")
            snapshotsToPersist.append(refreshedSnapshot)
            return plan.effectiveRate(from: refreshedSnapshot)
        }

        log(.warning, "静默刷新是否成功：否")

        if let cachedSnapshot {
            log(.warning, "静默刷新失败，继续使用旧缓存：\(plan.displayLabel)")
            if result.errors.isEmpty == false {
                log(.warning, result.errors.joined(separator: "；"))
            }
            return plan.effectiveRate(from: cachedSnapshot)
        }

        if result.errors.isEmpty == false {
            log(.error, result.errors.joined(separator: "；"))
        } else {
            log(.error, "静默刷新未返回可用汇率：\(plan.displayLabel)")
        }

        return nil
    }

    private func persistOperationArtifacts(
        logs: [RefreshLogEntry],
        snapshots: [CurrencySnapshot]
    ) async {
        guard logs.isEmpty == false || snapshots.isEmpty == false else {
            return
        }

        var latestState = await store.load() ?? .empty
        latestState.mergeSnapshots(deduplicatedSnapshots(from: snapshots))
        latestState.prependLogs(logs)
        await store.save(latestState)
        snapshotMergeHandler(snapshots)
    }

    private func deduplicatedSnapshots(from snapshots: [CurrencySnapshot]) -> [CurrencySnapshot] {
        Array(Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) }).values)
    }

    private func decimalValue(_ number: NSDecimalNumber) -> Decimal {
        number.decimalValue
    }

    private func redactedInputSummary(_ text: String) -> String {
        guard !text.isEmpty else {
            return "空文本"
        }

        let containsDigit = text.contains(where: \.isNumber)
        let containsLetter = text.contains(where: \.isLetter)
        let containsCurrencySymbol = text.contains { "$¥￥€£₽₩₺".contains($0) }

        var markers: [String] = []
        if containsDigit {
            markers.append("含数字")
        }
        if containsLetter {
            markers.append("含字母")
        }
        if containsCurrencySymbol {
            markers.append("含货币符号")
        }

        let markerText = markers.isEmpty ? "未识别到显著特征" : markers.joined(separator: "、")
        return "长度 \(text.count) 字符，\(markerText)"
    }
}

private struct ConversionRatePlan {
    let fetchPair: CurrencyPair
    let shouldInvert: Bool

    var displayLabel: String {
        shouldInvert ? "\(fetchPair.quoteCode)/\(fetchPair.baseCode)（复用 \(fetchPair.compactLabel) 反向换算）" : fetchPair.compactLabel
    }

    static func make(sourceCurrencyCode: String, targetCurrencyCode: String) -> ConversionRatePlan? {
        if let directPair = CurrencyCatalog.supportedPair(baseCode: sourceCurrencyCode, quoteCode: targetCurrencyCode) {
            return ConversionRatePlan(fetchPair: directPair, shouldInvert: false)
        }

        if let inversePair = CurrencyCatalog.supportedPair(baseCode: targetCurrencyCode, quoteCode: sourceCurrencyCode) {
            return ConversionRatePlan(fetchPair: inversePair, shouldInvert: true)
        }

        return nil
    }

    func effectiveRate(from snapshot: CurrencySnapshot) -> Double? {
        guard snapshot.rate > 0 else {
            return nil
        }

        return shouldInvert ? (1 / snapshot.rate) : snapshot.rate
    }
}
