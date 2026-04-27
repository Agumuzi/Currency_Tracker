//
//  ExchangePanelViewModel.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation
import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class ExchangePanelViewModel {
    var cards: [CurrencyCardModel]
    var isRefreshing = false
    var statusMessage: String?
    var statusSymbolName = "info.circle.fill"
    var statusColor = Color.secondary
    var statusBackgroundColor = Color.gray.opacity(0.10)
    var lastRefreshAttempt: Date?
    var sourceStatuses: [SourceStatus] = []
    var refreshLog: [RefreshLogEntry] = []

    @ObservationIgnored private let service: ExchangeRateService
    @ObservationIgnored private let store: ExchangeRateStore
    @ObservationIgnored private let preferences: PreferencesStore
    @ObservationIgnored private let credentialStore: EnhancedSourceCredentialStore
    @ObservationIgnored private var cachedState: CachedExchangeState
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPairIDs: Set<String> = []
    @ObservationIgnored private var unavailablePairIDs: Set<String> = []
    @ObservationIgnored private var isPanelPinned = false

    init(
        preferences: PreferencesStore,
        credentialStore: EnhancedSourceCredentialStore,
        service: ExchangeRateService? = nil,
        store: ExchangeRateStore = ExchangeRateStore(),
        previewState: CachedExchangeState? = nil
    ) {
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.service = service ?? ExchangeRateService()
        self.store = store
        self.cachedState = previewState ?? CachedExchangeState(snapshots: [], history: [:], lastRefreshAttempt: nil, refreshLog: [])
        self.cards = []

        if let previewState {
            lastRefreshAttempt = previewState.lastRefreshAttempt
            refreshLog = previewState.refreshLog
            statusMessage = String(localized: "预览数据")
            statusSymbolName = "eye.fill"
            statusColor = .secondary
            statusBackgroundColor = Color.gray.opacity(0.08)
        }

        updateCards()
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    var footerTimestampText: String {
        if let latestUpdate = cards.compactMap(\.snapshot?.updatedAt).max() {
            return String(
                format: String(localized: "上次更新 %@"),
                ExchangeFormatter.time.string(from: latestUpdate)
            )
        }

        if let lastRefreshAttempt {
            return String(
                format: String(localized: "上次检查 %@"),
                ExchangeFormatter.time.string(from: lastRefreshAttempt)
            )
        }

        return String(localized: "尚未更新")
    }

    var featuredPairID: String {
        preferences.selectedPairs.first?.id ?? preferences.featuredPairID
    }

    var menuBarHelpText: String {
        guard !preferences.selectedPairs.isEmpty else {
            return String(localized: "请先在设置中选择至少一个货币对")
        }

        guard let featuredCard else {
            return statusMessage ?? String(localized: "准备刷新")
        }

        var segments = [featuredCard.pair.subtitle]

        switch featuredCard.state {
        case .loading:
            segments.append(String(localized: "等待首次拉取"))
        case .failed:
            segments.append(String(localized: "当前重点货币对暂不可用"))
        case .ready, .stale:
            segments.append(String(format: String(localized: "当前 %@"), featuredCard.valueText))
            if !featuredCard.detailSegments.isEmpty {
                segments.append(featuredCard.detailSegments.joined(separator: " · "))
            }
        }

        return segments.joined(separator: " · ")
    }

    func shouldAutoRefreshOnOpen(now: Date = .now) -> Bool {
        RefreshPolicy.shouldAutoRefreshOnOpen(
            lastSuccessfulRefreshAt: cachedState.lastSuccessfulRefreshAt,
            isEnabled: preferences.menuBarOpenRefreshEnabled,
            isPinned: isPanelPinned,
            now: now
        ) == .refresh
    }

    func bootstrap() async {
        guard !didBootstrap else {
            return
        }

        didBootstrap = true

        if let cachedState = await store.load() {
            self.cachedState = markLoadedStateAsCached(cachedState)
            lastRefreshAttempt = cachedState.lastRefreshAttempt
            refreshLog = cachedState.refreshLog

            let cachedSnapshotIDs = Set(cachedState.snapshots.map(\.id))
            pendingPairIDs = Set(preferences.selectedPairs.map(\.id)).subtracting(cachedSnapshotIDs)
            unavailablePairIDs = []

            updateCards()
            configureStatus(
                message: cards.isEmpty ? String(localized: "请先在设置里添加要展示的货币对") : String(localized: "已加载上次成功结果"),
                symbolName: cards.isEmpty ? "slider.horizontal.3" : "clock.arrow.circlepath",
                tint: .secondary,
                background: Color.gray.opacity(0.08)
            )
        } else {
            pendingPairIDs = Set(preferences.selectedPairs.map(\.id))
            unavailablePairIDs = []
            updateCards()

            configureStatus(
                message: String(localized: "暂无缓存，准备首次拉取汇率数据"),
                symbolName: "tray.fill",
                tint: .secondary,
                background: Color.gray.opacity(0.08)
            )
        }

        restartAutomaticRefresh()
        await refresh(trigger: .bootstrap)
    }

    func menuBarPanelDidOpen() async {
        guard didBootstrap else {
            return
        }

        switch RefreshPolicy.shouldAutoRefreshOnOpen(
            lastSuccessfulRefreshAt: cachedState.lastSuccessfulRefreshAt,
            isEnabled: preferences.menuBarOpenRefreshEnabled,
            isPinned: isPanelPinned
        ) {
        case .refresh:
            recordInternalEvent("菜单栏打开，触发自动刷新")
            await refresh(trigger: .panelOpen)
        case .skippedBecauseDisabled:
            recordInternalEvent("菜单栏自动刷新已跳过：已关闭“点开菜单栏时自动刷新”")
        case .skippedBecausePinned:
            recordInternalEvent("菜单栏自动刷新已跳过：当前面板处于锁定状态")
        case .skippedBecauseThrottle:
            recordInternalEvent("菜单栏自动刷新已跳过：10 分钟节流未到")
        }
    }

    func refresh(trigger: RefreshTrigger) async {
        guard !isRefreshing else {
            return
        }

        if trigger.isAutomatic && isPanelPinned {
            recordInternalEvent("\(trigger.logLabel)已跳过：当前面板处于锁定状态")
            return
        }

        let selectedPairs = preferences.selectedPairs
        let selectedPairIDs = Set(selectedPairs.map(\.id))

        guard !selectedPairs.isEmpty else {
            pendingPairIDs = []
            unavailablePairIDs = []
            updateCards()
            appendLog(level: .warning, message: "刷新跳过，当前没有已选货币对")
            configureStatus(
                message: String(localized: "请先在设置中选择至少一个货币对"),
                symbolName: "slider.horizontal.3",
                tint: .secondary,
                background: Color.gray.opacity(0.08)
            )
            await persistCachedState()
            return
        }

        let existingSnapshotIDs = Set(cachedState.snapshots.map(\.id))
        let unresolvedBeforeRefresh = selectedPairIDs.subtracting(existingSnapshotIDs)
        pendingPairIDs.formUnion(unresolvedBeforeRefresh)
        unavailablePairIDs.subtract(selectedPairIDs)
        updateCards()

        isRefreshing = true
        defer { isRefreshing = false }

        let refreshMoment = Date()
        lastRefreshAttempt = refreshMoment
        cachedState.lastRefreshAttempt = refreshMoment
        if trigger.isAutomatic {
            cachedState.lastAutomaticRefreshAttempt = refreshMoment
        }

        let currentSnapshots = Dictionary(
            uniqueKeysWithValues: cachedState.snapshots.map { ($0.id, $0.withCacheFlag(true)) }
        )
        var mergedSnapshots = currentSnapshots
        var history = cachedState.history
        let sourceConfiguration = credentialStore.configuration.withCustomProviders(preferences.enabledCustomAPIProviders)

        let shouldRefreshHistory = RefreshPolicy.shouldRefreshHistory(
            lastHistoricalRefreshAt: cachedState.lastHistoricalRefresh,
            cachedHistoryPairIDs: Set(history.keys),
            selectedPairIDs: selectedPairIDs,
            now: refreshMoment
        ) == .refresh

        async let latestSnapshots = service.fetchSnapshots(for: selectedPairs, configuration: sourceConfiguration)

        let result = await latestSnapshots
        let historyResult = shouldRefreshHistory
            ? await service.fetchHistoricalSeries(for: selectedPairs)
            : HistoricalFetchResult(historyByPairID: [:], errors: [])
        sourceStatuses = result.sourceStatuses

        for log in result.logs {
            appendLog(level: log.level, message: log.message)
        }

        for snapshot in result.snapshots {
            mergedSnapshots[snapshot.id] = snapshot
        }
        await processRateAlerts(with: result.snapshots)

        for (pairID, points) in historyResult.historyByPairID where !points.isEmpty {
            history[pairID] = points
        }

        if shouldRefreshHistory {
            cachedState.lastHistoricalRefresh = refreshMoment
            appendLog(level: .info, message: "历史曲线已按低频策略刷新")
        }

        if !result.snapshots.isEmpty {
            cachedState.lastSuccessfulRefreshAt = refreshMoment
        }

        if !historyResult.errors.isEmpty {
            appendLog(level: .warning, message: historyResult.errors.joined(separator: "；"))
        }

        pendingPairIDs.subtract(selectedPairIDs)
        unavailablePairIDs = selectedPairIDs.subtracting(Set(mergedSnapshots.keys))

        cachedState = CachedExchangeState(
            snapshots: Array(mergedSnapshots.values),
            history: history,
            lastRefreshAttempt: refreshMoment,
            lastSuccessfulRefreshAt: cachedState.lastSuccessfulRefreshAt,
            lastAutomaticRefreshAttempt: cachedState.lastAutomaticRefreshAttempt,
            lastHistoricalRefresh: cachedState.lastHistoricalRefresh,
            refreshLog: refreshLog
        )

        if result.snapshots.isEmpty {
            updateCards()
            appendLog(level: .error, message: result.errors.joined(separator: "；").isEmpty ? "刷新失败" : result.errors.joined(separator: "；"))
            configureStatus(
                message: unavailablePairIDs.isEmpty ? String(localized: "刷新失败，继续显示上次成功结果") : String(localized: "刷新失败，部分货币对暂不可用"),
                symbolName: "exclamationmark.triangle.fill",
                tint: Color(red: 0.72, green: 0.43, blue: 0.08),
                background: Color(red: 0.98, green: 0.93, blue: 0.82)
            )
            await persistCachedState()
            return
        }

        if result.errors.isEmpty && unavailablePairIDs.isEmpty {
            appendLog(level: .info, message: "刷新成功，\(result.snapshots.count) 个货币对已更新")
            configureStatus(
                message: String(localized: "数据已更新"),
                symbolName: "checkmark.circle.fill",
                tint: Color(red: 0.09, green: 0.53, blue: 0.32),
                background: Color(red: 0.87, green: 0.95, blue: 0.90)
            )
        } else {
            let unresolvedText = unavailablePairIDs.isEmpty ? nil : "仍有 \(unavailablePairIDs.count) 个货币对没有可展示数据"
            let errorSegments = (result.errors + [unresolvedText].compactMap { $0 })
            appendLog(level: .warning, message: errorSegments.joined(separator: "；"))
            configureStatus(
                message: unavailablePairIDs.isEmpty ? String(localized: "部分来源刷新失败，已保留可用结果") : String(localized: "部分货币对未更新，已保留可用结果"),
                symbolName: "exclamationmark.circle.fill",
                tint: Color(red: 0.70, green: 0.35, blue: 0.05),
                background: Color(red: 0.98, green: 0.93, blue: 0.84)
            )
        }

        updateCards()
        await persistCachedState()
    }

    func selectedPairsDidChange() async {
        let selectedPairIDs = Set(preferences.selectedPairs.map(\.id))
        pendingPairIDs = pendingPairIDs.intersection(selectedPairIDs)
        unavailablePairIDs = unavailablePairIDs.intersection(selectedPairIDs)

        updateCards()
        restartAutomaticRefresh()

        guard !preferences.selectedPairs.isEmpty else {
            pendingPairIDs = []
            unavailablePairIDs = []
            configureStatus(
                message: String(localized: "请先在设置中选择至少一个货币对"),
                symbolName: "slider.horizontal.3",
                tint: .secondary,
                background: Color.gray.opacity(0.08)
            )
            return
        }

        let snapshotIDs = Set(cachedState.snapshots.map(\.id))
        let missingPairIDs = selectedPairIDs.subtracting(snapshotIDs)
        guard !missingPairIDs.isEmpty else {
            return
        }

        pendingPairIDs.formUnion(missingPairIDs)
        unavailablePairIDs.subtract(missingPairIDs)
        updateCards()

        await refresh(trigger: .selectionChange)
    }

    func refreshPolicyDidChange() {
        restartAutomaticRefresh()
    }

    func setPanelPinned(_ isPinned: Bool) {
        isPanelPinned = isPinned
        restartAutomaticRefresh()
    }

    func trendStorageDidChange() async {
        updateCards()
        await persistCachedState()
    }

    func presentationDidChange() {
        updateCards()
    }

    private func updateCards() {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: cachedState.snapshots.map { ($0.id, $0) })
        cards = preferences.selectedPairs.map { pair in
            let snapshot = snapshotsByID[pair.id]
            let historyPoints = cachedState.history[pair.id] ?? []
            let previousValue = historyPoints.dropLast().last?.value

            let state: CurrencyCardState
            if let snapshot {
                state = snapshot.isCached ? .stale : .ready
            } else if pendingPairIDs.contains(pair.id) || !didBootstrap || lastRefreshAttempt == nil {
                state = .loading
            } else if unavailablePairIDs.contains(pair.id) {
                state = .failed
            } else {
                state = .loading
            }

            return CurrencyCardModel(
                pair: pair,
                snapshot: snapshot,
                historyPoints: historyPoints,
                previousValue: previousValue,
                state: state,
                sampleLimit: max(preferences.trendPointLimit, 36)
            )
        }
    }

    private var featuredCard: CurrencyCardModel? {
        cards.first { $0.id == featuredPairID } ?? cards.first
    }

    private func appendLog(level: RefreshLogEntry.Level, message: String) {
        let entry = RefreshLogEntry(timestamp: .now, level: level, message: message)
        refreshLog.insert(entry, at: 0)
        refreshLog = Array(refreshLog.prefix(30))
        cachedState.refreshLog = refreshLog
    }

    func recordInternalEvent(_ message: String, level: RefreshLogEntry.Level = .info) {
        appendLog(level: level, message: message)
    }

    func mergeServiceSnapshots(_ snapshots: [CurrencySnapshot]) {
        guard !snapshots.isEmpty else {
            return
        }

        cachedState.mergeSnapshots(snapshots)
        updateCards()
    }

    private func restartAutomaticRefresh() {
        autoRefreshTask?.cancel()

        guard !isPanelPinned else {
            return
        }

        guard preferences.autoRefreshMinutes > 0 else {
            return
        }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let delay = UInt64(self.preferences.autoRefreshMinutes) * 60_000_000_000
                try? await Task.sleep(nanoseconds: delay)

                if Task.isCancelled {
                    return
                }

                await self.refresh(trigger: .scheduled)
            }
        }
    }

    private func persistCachedState() async {
        await store.save(cachedState)
    }

    private func markLoadedStateAsCached(_ state: CachedExchangeState) -> CachedExchangeState {
        CachedExchangeState(
            snapshots: state.snapshots.map { $0.withCacheFlag(true) },
            history: state.history,
            lastRefreshAttempt: state.lastRefreshAttempt,
            lastSuccessfulRefreshAt: state.lastSuccessfulRefreshAt,
            lastAutomaticRefreshAttempt: state.lastAutomaticRefreshAttempt,
            lastHistoricalRefresh: state.lastHistoricalRefresh,
            refreshLog: state.refreshLog
        )
    }

    private func configureStatus(message: String, symbolName: String, tint: Color, background: Color) {
        statusMessage = message
        statusSymbolName = symbolName
        statusColor = tint
        statusBackgroundColor = background
    }

    private func processRateAlerts(with snapshots: [CurrencySnapshot]) async {
        guard !snapshots.isEmpty else {
            return
        }

        let snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let now = Date()
        for alert in preferences.rateAlerts where alert.isEnabled {
            guard let snapshot = snapshotsByID[alert.pairID],
                  alert.isTriggered(by: snapshot.rate),
                  shouldTrigger(alert: alert, now: now) else {
                continue
            }

            preferences.setRateAlertTriggered(id: alert.id, at: now)
            recordInternalEvent("汇率提醒触发：\(snapshot.pair.compactLabel) \(alert.direction.title) \(alert.threshold)")
            await deliverRateAlertNotification(alert: alert, snapshot: snapshot)
        }
    }

    private func shouldTrigger(alert: RateAlert, now: Date) -> Bool {
        guard let lastTriggeredAt = alert.lastTriggeredAt else {
            return true
        }

        return now.timeIntervalSince(lastTriggeredAt) > 12 * 60 * 60
    }

    private func deliverRateAlertNotification(alert: RateAlert, snapshot: CurrencySnapshot) async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                recordInternalEvent("汇率提醒未弹出：通知权限未授权", level: .warning)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "汇率提醒")
            content.body = "\(snapshot.pair.compactLabel) \(alert.direction.title) \(ExchangeFormatter.decimal.string(from: alert.threshold as NSNumber) ?? "\(alert.threshold)")，\(String(localized: "当前")) \(snapshot.rate)"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "currency-tracker-rate-alert-\(alert.id.uuidString)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            recordInternalEvent("汇率提醒发送失败：\(error.localizedDescription)", level: .warning)
        }
    }
}
