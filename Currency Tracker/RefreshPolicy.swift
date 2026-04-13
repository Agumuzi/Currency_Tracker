//
//  RefreshPolicy.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import Foundation

enum RefreshTrigger: String, Sendable {
    case bootstrap
    case manual
    case scheduled
    case panelOpen
    case selectionChange

    var isAutomatic: Bool {
        switch self {
        case .manual, .selectionChange:
            false
        case .bootstrap, .scheduled, .panelOpen:
            true
        }
    }

    var logLabel: String {
        switch self {
        case .bootstrap:
            "启动刷新"
        case .manual:
            "手动刷新"
        case .scheduled:
            "定时刷新"
        case .panelOpen:
            "菜单栏打开刷新"
        case .selectionChange:
            "配置变更刷新"
        }
    }
}

enum PanelAutoRefreshDecision: Sendable, Equatable {
    case refresh
    case skippedBecauseDisabled
    case skippedBecausePinned
    case skippedBecauseThrottle
}

enum HistoryRefreshDecision: Sendable, Equatable {
    case refresh
    case skip
}

enum ServiceConversionRefreshDecision: Sendable, Equatable {
    case useCache
    case refreshSilently
}

enum RefreshPolicy {
    static let panelOpenThrottle: TimeInterval = 10 * 60
    static let historicalRefreshInterval: TimeInterval = 12 * 60 * 60
    static let serviceCacheMaxAge: TimeInterval = 60 * 60

    static func shouldAutoRefreshOnOpen(
        lastSuccessfulRefreshAt: Date?,
        isEnabled: Bool,
        isPinned: Bool,
        now: Date = .now
    ) -> PanelAutoRefreshDecision {
        if isEnabled == false {
            return .skippedBecauseDisabled
        }

        if isPinned {
            return .skippedBecausePinned
        }

        guard let lastSuccessfulRefreshAt else {
            return .refresh
        }

        return now.timeIntervalSince(lastSuccessfulRefreshAt) >= panelOpenThrottle
            ? .refresh
            : .skippedBecauseThrottle
    }

    static func shouldRefreshHistory(
        lastHistoricalRefreshAt: Date?,
        cachedHistoryPairIDs: Set<String>,
        selectedPairIDs: Set<String>,
        now: Date = .now
    ) -> HistoryRefreshDecision {
        guard !selectedPairIDs.isEmpty else {
            return .skip
        }

        if cachedHistoryPairIDs.isSuperset(of: selectedPairIDs) == false {
            return .refresh
        }

        guard let lastHistoricalRefreshAt else {
            return .refresh
        }

        return now.timeIntervalSince(lastHistoricalRefreshAt) >= historicalRefreshInterval
            ? .refresh
            : .skip
    }

    static func shouldRefreshServiceConversion(
        lastSuccessfulUpdateAt: Date?,
        now: Date = .now
    ) -> ServiceConversionRefreshDecision {
        guard let lastSuccessfulUpdateAt else {
            return .refreshSilently
        }

        return now.timeIntervalSince(lastSuccessfulUpdateAt) > serviceCacheMaxAge
            ? .refreshSilently
            : .useCache
    }
}
