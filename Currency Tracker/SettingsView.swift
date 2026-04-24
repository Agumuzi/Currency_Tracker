//
//  SettingsView.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Hashable, Sendable {
    case general
    case rates
    case refresh
    case dataSources
    case system

    var title: LocalizedStringKey {
        switch self {
        case .general:
            "通用"
        case .rates:
            "汇率"
        case .refresh:
            "刷新"
        case .dataSources:
            "数据源"
        case .system:
            "系统"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .general:
            "基准货币与文本换算"
        case .rates:
            "展示列表与新增汇率"
        case .refresh:
            "自动更新行为"
        case .dataSources:
            "API key 与增强来源"
        case .system:
            "开机启动"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "gearshape"
        case .rates:
            "list.bullet.rectangle"
        case .refresh:
            "arrow.clockwise"
        case .dataSources:
            "key"
        case .system:
            "power"
        }
    }
}

struct SettingsView: View {
    let preferences: PreferencesStore
    let launchController: LaunchAtLoginController
    let viewModel: ExchangePanelViewModel
    let apiConfigurationViewModel: APIConfigurationViewModel
    let globalShortcutHandler: GlobalShortcutHandler
    let focusSection: SettingsSection?

    @State private var draftBaseCode = "USD"
    @State private var draftQuoteCode = "RUB"
    @State private var currencySearch = ""
    @State private var draggedPairID: String?
    @State private var selectedSection: SettingsSection = .rates
    @State private var isShowingAPIPrivacyDetails = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader
                    selectedPageContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 880, height: 600, alignment: .topLeading)
        .background(windowBackground)
        .onAppear {
            syncDraftSelectionToSearchResults()
            apiConfigurationViewModel.reloadFromStore()
            applyFocusedSection()
        }
        .onChange(of: currencySearch) { _, _ in
            syncDraftSelectionToSearchResults()
        }
        .onChange(of: focusSection) { _, _ in
            applyFocusedSection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            appHeader

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    sidebarButton(for: section)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 252)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
    }

    private var appHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Currency Tracker")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("管理汇率展示、刷新行为和系统级文本换算入口")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedSection.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(selectedSection.subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedPageContent: some View {
        switch selectedSection {
        case .general:
            baseCurrencySection
            textConversionShortcutSection
        case .rates:
            selectedPairsSection
            addPairSection
        case .refresh:
            refreshBehaviorSection
        case .dataSources:
            apiConfigurationSection
        case .system:
            launchSection
        }
    }

    private func sidebarButton(for section: SettingsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(section.subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.sidebar.\(section.rawValue)")
    }

    private var baseCurrencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("基准货币")

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("系统级换算统一输出到这里")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("菜单栏面板、Services、全局快捷键和剪贴板结果都会统一使用这个币种。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("基准货币", selection: Binding(
                    get: { preferences.baseCurrencyCode },
                    set: { preferences.setBaseCurrencyCode($0) }
                )) {
                    ForEach(preferences.availableBaseCurrencyOptions) { currency in
                        Text("\(CurrencyCatalog.name(for: currency.code)) · \(currency.code)")
                            .tag(currency.code)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var refreshBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("刷新行为")

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("点开菜单栏时自动刷新")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("关闭后，只有手动刷新和定时刷新会更新数据。")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { preferences.menuBarOpenRefreshEnabled },
                        set: {
                            preferences.setMenuBarOpenRefreshEnabled($0)
                            viewModel.refreshPolicyDidChange()
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("定时自动刷新")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("固定窗口后会自动暂停；解锁后恢复。")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("自动刷新间隔", selection: Binding(
                        get: { preferences.autoRefreshMinutes },
                        set: {
                            preferences.setAutoRefreshMinutes($0)
                            viewModel.refreshPolicyDidChange()
                        }
                    )) {
                        ForEach(preferences.autoRefreshIntervalOptions, id: \.self) { value in
                            Text(refreshIntervalTitle(for: value))
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var textConversionShortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("文本换算快捷键")

            VStack(alignment: .leading, spacing: 16) {
                Text("选中文本后按下这里设置的全局快捷键，会直接触发与 Services 相同的“换算为基准货币”流程。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                GlobalShortcutRecorderView(shortcut: preferences.textConversionShortcut) { shortcut in
                    preferences.setTextConversionShortcut(shortcut)
                    globalShortcutHandler.refreshRegistration()
                }

                Text("如果某些应用不能直接读取选中文本，应用会自动回退到复制方式；首次使用时系统可能要求辅助功能权限。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var selectedPairsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("已添加汇率")
                Spacer()
                countBadge(preferences.selectedPairs.count)
            }

            if preferences.selectedPairs.isEmpty {
                Text("还没有添加汇率")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(sectionCardBackground)
                    .accessibilityIdentifier("settings.empty-pairs")
            } else {
                VStack(spacing: 10) {
                    ForEach(preferences.selectedPairs) { pair in
                        HStack(spacing: 12) {
                            dragHandle

                            VStack(alignment: .leading, spacing: 4) {
                                Text(pair.displayName)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text(pair.subtitle)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            pairOrderControls(for: pair)

                            Button("移除") {
                                preferences.removePair(id: pair.id)
                                Task {
                                    await viewModel.selectedPairsDidChange()
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sectionCardBackground)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .onDrag {
                            draggedPairID = pair.id
                            return NSItemProvider(object: pair.id as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: PairReorderDropDelegate(
                            targetPairID: pair.id,
                            draggedPairID: $draggedPairID,
                            preferences: preferences,
                            viewModel: viewModel
                        ))
                    }
                }

                if preferences.selectedPairs.count > 1 {
                    dropToBottomStrip
                }
            }
        }
    }

    private var addPairSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("添加汇率")

            VStack(alignment: .leading, spacing: 14) {
                TextField("搜索币种代码、中文名或英文名", text: $currencySearch)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.currency-search")

                if canShowDraftPickers {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 10) {
                            currencyPickerColumn(
                                title: "基础货币",
                                selection: $draftBaseCode,
                                currencies: filteredBaseCurrencies
                            )
                            .onChange(of: draftBaseCode) { _, newValue in
                                let quotes = preferences.availableQuoteCurrencies(for: newValue)
                                if quotes.contains(where: { $0.code == draftQuoteCode }) == false {
                                    draftQuoteCode = quotes.first?.code ?? "RUB"
                                }
                                syncDraftSelectionToSearchResults()
                            }

                            Button {
                                swapDraftCurrencies()
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                            .disabled(canSwapDraftCurrencies == false)
                            .help("调换货币")

                            currencyPickerColumn(
                                title: "目标货币",
                                selection: $draftQuoteCode,
                                currencies: filteredQuoteCurrencies
                            )
                        }

                        Button("加入展示") {
                            preferences.addPair(baseCode: draftBaseCode, quoteCode: draftQuoteCode)
                            Task {
                                await viewModel.selectedPairsDidChange()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentDraftPair == nil || currentDraftAlreadySelected)
                        .accessibilityIdentifier("settings.add-pair")
                    }
                } else {
                    searchEmptyState
                }

                if currentDraftAlreadySelected {
                    Text("这个汇率已经存在")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var apiConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("数据增强")

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("留空则继续使用默认公共数据源；API key 只用于增强最新快照。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    DisclosureGroup("详细说明", isExpanded: $isShowingAPIPrivacyDetails) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("只有在你点击“保存”后，API 信息才会写入本地凭证文件（Application Support/CurrencyTracker）。")
                            Text("外部数据源只能看到本次汇率请求本身及常规网络元数据；应用不会上传本地文件、剪贴板或其他设备内容，并且请求会强制走 HTTPS。")
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                }

                APIConfigurationRow(
                    field: apiConfigurationViewModel.field(for: .twelveData),
                    onValueChange: { apiConfigurationViewModel.updateDraft($0, for: .twelveData) },
                    onToggleReveal: { apiConfigurationViewModel.toggleReveal(for: .twelveData) },
                    onPrimaryAction: {
                        await apiConfigurationViewModel.performPrimaryAction(for: .twelveData)
                    }
                )

                APIConfigurationRow(
                    field: apiConfigurationViewModel.field(for: .openExchangeRates),
                    onValueChange: { apiConfigurationViewModel.updateDraft($0, for: .openExchangeRates) },
                    onToggleReveal: { apiConfigurationViewModel.toggleReveal(for: .openExchangeRates) },
                    onPrimaryAction: {
                        await apiConfigurationViewModel.performPrimaryAction(for: .openExchangeRates)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("启动")

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开机自动启动")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    if let lastErrorMessage = launchController.lastErrorMessage {
                        Text(lastErrorMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { launchController.isEnabled || launchController.requiresApproval },
                    set: { launchController.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)

            if launchController.requiresApproval {
                Button("打开系统设置") {
                    launchController.openSystemSettings()
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        }
    }

    private var currentDraftPair: CurrencyPair? {
        CurrencyCatalog.supportedPair(baseCode: draftBaseCode, quoteCode: draftQuoteCode)
    }

    private var hasSearchKeyword: Bool {
        !searchKeyword.isEmpty
    }

    private var filteredBaseCurrencies: [CurrencyInfo] {
        filter(currencies: preferences.availableBaseCurrencies)
    }

    private var filteredQuoteCurrencies: [CurrencyInfo] {
        filter(currencies: preferences.availableQuoteCurrencies(for: draftBaseCode))
    }

    private var currentDraftAlreadySelected: Bool {
        guard let currentDraftPair else {
            return false
        }

        return preferences.contains(currentDraftPair)
    }

    private var canShowDraftPickers: Bool {
        !filteredBaseCurrencies.isEmpty && !filteredQuoteCurrencies.isEmpty
    }

    private var searchKeyword: String {
        currencySearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .help("拖动调整展示顺序")
    }

    private func pairOrderControls(for pair: CurrencyPair) -> some View {
        HStack(spacing: 2) {
            Button {
                preferences.movePairUp(id: pair.id)
                viewModel.presentationDidChange()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(preferences.selectedPairIDs.first == pair.id)
            .help("上移")

            Button {
                preferences.movePairDown(id: pair.id)
                viewModel.presentationDidChange()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(preferences.selectedPairIDs.last == pair.id)
            .help("下移")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func currencyPickerColumn(
        title: LocalizedStringKey,
        selection: Binding<String>,
        currencies: [CurrencyInfo]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(currencies) { currency in
                    Text("\(CurrencyCatalog.name(for: currency.code)) · \(currency.code)")
                        .tag(currency.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dropToBottomStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 11, weight: .semibold))
            Text("拖到这里放到末尾")
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .onDrop(of: [UTType.text], delegate: PairListDropDelegate(
            draggedPairID: $draggedPairID,
            preferences: preferences,
            viewModel: viewModel
        ))
    }

    private var sectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
    }

    private var windowBackground: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    private func filter(currencies: [CurrencyInfo]) -> [CurrencyInfo] {
        guard hasSearchKeyword else {
            return currencies
        }

        return currencies.filter { currency in
            CurrencyCatalog.matchesSearch(currency, query: searchKeyword)
        }
    }

    private func syncDraftSelectionToSearchResults() {
        if let firstBase = filteredBaseCurrencies.first,
           filteredBaseCurrencies.contains(where: { $0.code == draftBaseCode }) == false {
            draftBaseCode = firstBase.code
        }

        if let firstQuote = filteredQuoteCurrencies.first,
           filteredQuoteCurrencies.contains(where: { $0.code == draftQuoteCode }) == false {
            draftQuoteCode = firstQuote.code
        }
    }

    private var canSwapDraftCurrencies: Bool {
        CurrencyCatalog.supportedPair(baseCode: draftQuoteCode, quoteCode: draftBaseCode) != nil
    }

    private func swapDraftCurrencies() {
        guard canSwapDraftCurrencies else {
            return
        }

        let previousBase = draftBaseCode
        draftBaseCode = draftQuoteCode
        draftQuoteCode = previousBase
        syncDraftSelectionToSearchResults()
    }

    private var searchEmptyState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            Text("没有匹配的币种")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func refreshIntervalTitle(for value: Int) -> String {
        switch value {
        case 0:
            String(localized: "关闭")
        case 5:
            String(localized: "5 分钟")
        case 10:
            String(localized: "10 分钟")
        case 30:
            String(localized: "30 分钟")
        case 60:
            String(localized: "1 小时")
        default:
            String(format: String(localized: "%d 分钟"), value)
        }
    }

    private func applyFocusedSection() {
        guard let focusSection else {
            return
        }

        selectedSection = focusSection
    }
}

private struct APIConfigurationRow: View {
    let field: APIFieldState
    let onValueChange: (String) -> Void
    let onToggleReveal: () -> Void
    let onPrimaryAction: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(field.kind.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))

                Spacer()

                Text(LocalizedStringKey(field.phase.statusText))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(field.phase.tintColor)
                    .accessibilityLabel(field.phase.statusText)
                    .accessibilityIdentifier("\(identifierPrefix).status")
            }

            HStack(spacing: 8) {
                Group {
                    if field.isRevealed {
                        TextField(LocalizedStringKey(field.kind.placeholder), text: Binding(
                            get: { field.draftValue },
                            set: onValueChange
                        ))
                    } else {
                        SecureField(LocalizedStringKey(field.kind.placeholder), text: Binding(
                            get: { field.draftValue },
                            set: onValueChange
                        ))
                    }
                }
                .textFieldStyle(.roundedBorder)
                .disabled(field.isEditing == false)
                .accessibilityIdentifier("\(identifierPrefix).input")

                Button {
                    onToggleReveal()
                } label: {
                    Image(systemName: field.isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(field.draftValue.isEmpty ? .tertiary : .secondary)
                .disabled(field.draftValue.isEmpty)
                .accessibilityIdentifier("\(identifierPrefix).reveal")

                Group {
                    if field.isEditing {
                        Button(LocalizedStringKey(field.buttonTitle)) {
                            Task {
                                await onPrimaryAction()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(LocalizedStringKey(field.buttonTitle)) {
                            Task {
                                await onPrimaryAction()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.small)
                .disabled(field.phase == .saving)
                .accessibilityIdentifier("\(identifierPrefix).primary")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var identifierPrefix: String {
        "settings.api.\(field.kind.rawValue)"
    }
}

private struct PairReorderDropDelegate: DropDelegate {
    let targetPairID: String
    @Binding var draggedPairID: String?
    let preferences: PreferencesStore
    let viewModel: ExchangePanelViewModel

    func dropEntered(info: DropInfo) {
        guard let draggedPairID,
              draggedPairID != targetPairID,
              let fromIndex = preferences.selectedPairIDs.firstIndex(of: draggedPairID),
              let toIndex = preferences.selectedPairIDs.firstIndex(of: targetPairID) else {
            return
        }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        preferences.movePair(id: draggedPairID, to: destination)
        viewModel.presentationDidChange()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedPairID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

private struct PairListDropDelegate: DropDelegate {
    @Binding var draggedPairID: String?
    let preferences: PreferencesStore
    let viewModel: ExchangePanelViewModel

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedPairID else {
            return false
        }

        preferences.movePair(id: draggedPairID, to: preferences.selectedPairIDs.count)
        viewModel.presentationDidChange()
        self.draggedPairID = nil
        return true
    }
}
