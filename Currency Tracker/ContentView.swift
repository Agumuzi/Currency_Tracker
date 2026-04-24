//
//  ContentView.swift
//  Currency Tracker
//
//  Created by Thomas Tao on 4/10/26.
//

import AppKit
import SwiftUI

struct ContentView: View {
    let viewModel: ExchangePanelViewModel
    let preferences: PreferencesStore
    let settingsWindowController: SettingsWindowController
    let panelWindowController: PanelWindowController
    let autoBootstrap: Bool
    let presentationMode: PanelPresentationMode

    @State private var expandedCardID: String?
    @State private var currentWindow: NSWindow?
    @State private var isShowingQuickAddPanel = false

    var body: some View {
        VStack(spacing: 12) {
            panelHeader
            compactStatusBanner
            cardList
            footer
        }
        .padding(16)
        .frame(width: 392, height: panelHeight, alignment: .top)
        .background(panelBackground)
        .task {
            if autoBootstrap {
                await viewModel.bootstrap()
            }
        }
        .onAppear {
            resizePinnedWindowIfNeeded()
        }
        .background(
            WindowEventObserver(
                onResolveWindow: {
                    currentWindow = $0
                    panelWindowController.registerMenuBarWindow($0)
                    resizePinnedWindowIfNeeded()
                },
                onBecomeKey: {
                    guard presentationMode == .menuBar else {
                        return
                    }

                    panelWindowController.dismissTransientMenuWindowIfNeeded(currentWindow)
                    guard panelWindowController.isPinned == false else {
                        return
                    }

                    Task {
                        await viewModel.menuBarPanelDidOpen()
                    }
                }
            )
        )
        .onChange(of: viewModel.cards.map(\.id)) { _, ids in
            if let expandedCardID, ids.contains(expandedCardID) == false {
                self.expandedCardID = nil
            }
        }
        .onChange(of: panelHeight) { _, _ in
            resizePinnedWindowIfNeeded()
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Currency Tracker")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            panelActions
        }
    }

    private var panelActions: some View {
        HStack(spacing: 8) {
            Button {
                isShowingQuickAddPanel = true
            } label: {
                toolbarButtonLabel(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("快速添加货币对")
            .popover(isPresented: $isShowingQuickAddPanel, arrowEdge: .top) {
                QuickAddPairPopover(
                    preferences: preferences,
                    viewModel: viewModel,
                    onClose: { isShowingQuickAddPanel = false }
                )
            }

            Button {
                panelWindowController.togglePinnedPanel(from: currentWindow)
            } label: {
                toolbarButtonLabel(systemName: panelWindowController.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(panelWindowController.isPinned ? Color.accentColor : .secondary)
            .help(panelWindowController.isPinned ? "解除锁定" : "锁定面板")

            Button {
                Task {
                    await viewModel.refresh(trigger: .manual)
                }
            } label: {
                toolbarButtonLabel(systemName: viewModel.isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
            .help(viewModel.isRefreshing ? "正在刷新" : "立即刷新")

            Menu {
                Section("刷新与数据") {
                    Button("立即刷新") {
                        Task {
                            await viewModel.refresh(trigger: .manual)
                        }
                    }
                    .disabled(viewModel.isRefreshing)

                    Toggle(
                        "点开菜单栏时自动刷新",
                        isOn: Binding(
                            get: { preferences.menuBarOpenRefreshEnabled },
                            set: {
                                preferences.setMenuBarOpenRefreshEnabled($0)
                                viewModel.refreshPolicyDidChange()
                            }
                        )
                    )

                    Menu("自动刷新间隔") {
                        ForEach(preferences.autoRefreshIntervalOptions, id: \.self) { value in
                            Button {
                                preferences.setAutoRefreshMinutes(value)
                                viewModel.refreshPolicyDidChange()
                            } label: {
                                HStack {
                                    Text(refreshIntervalTitle(for: value))
                                    if preferences.autoRefreshMinutes == value {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("设置与行为") {
                    Button("API 设置…") {
                        settingsWindowController.show(section: .dataSources)
                    }

                    Button("基准货币设置…") {
                        settingsWindowController.show(section: .general)
                    }

                    Button("文本换算快捷键设置…") {
                        settingsWindowController.show(section: .general)
                    }

                    Button("打开完整设置窗口") {
                        settingsWindowController.show()
                    }
                }

                Section("应用动作") {
                    Button("退出应用") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            } label: {
                toolbarButtonLabel(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("更多")
        }
    }

    private var headerSubtitle: String {
        guard !preferences.selectedPairs.isEmpty else {
            return String(localized: "尚未添加汇率")
        }

        return String(
            format: String(localized: "基准 %@ · %d 个汇率"),
            preferences.baseCurrencyCode,
            preferences.selectedPairs.count
        )
    }

    @ViewBuilder
    private var compactStatusBanner: some View {
        if let message = viewModel.statusMessage, shouldShowStatusBanner {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: viewModel.statusSymbolName)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(viewModel.statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(viewModel.statusBackgroundColor)
            )
        }
    }

    @ViewBuilder
    private var cardList: some View {
        if preferences.selectedPairs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("还没有要展示的货币对")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("点击右上角 + 快速加入需要展示的汇率，或在 … 里打开完整设置窗口。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Button {
                    isShowingQuickAddPanel = true
                } label: {
                    Label("添加汇率", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(maxWidth: .infinity, minHeight: cardAreaHeight, maxHeight: cardAreaHeight, alignment: .topLeading)
        } else if shouldScrollCards {
            ScrollView(.vertical, showsIndicators: false) {
                cardStack
            }
            .frame(maxWidth: .infinity, minHeight: cardAreaHeight, maxHeight: cardAreaHeight, alignment: .top)
        } else {
            cardStack
                .frame(maxWidth: .infinity, minHeight: cardAreaHeight, maxHeight: cardAreaHeight, alignment: .top)
        }
    }

    private var cardStack: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.cards) { card in
                CurrencyCardView(
                    card: card,
                    isFeatured: card.id == viewModel.featuredPairID,
                    showsFlags: preferences.showsFlags,
                    isExpanded: expandedCardID == card.id,
                    expandedCardID: $expandedCardID
                )
            }
        }
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(viewModel.footerTimestampText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if panelWindowController.isPinned {
                Label("已固定", systemImage: "pin.fill")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        )
        .padding(.top, 8)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.045), radius: 8, y: 4)
    }

    private var shouldShowStatusBanner: Bool {
        if preferences.selectedPairs.isEmpty {
            return true
        }

        return viewModel.statusSymbolName.contains("exclamationmark") || viewModel.cards.contains { $0.state != .ready }
    }

    private var maximumCardAreaHeight: CGFloat {
        maximumPanelHeight - chromeHeight
    }

    private var estimatedCardsHeight: CGFloat {
        let total = viewModel.cards.reduce(CGFloat.zero) { partialResult, card in
            partialResult + estimatedHeight(for: card)
        }

        return total + CGFloat(max(0, viewModel.cards.count - 1)) * 12
    }

    private var shouldScrollCards: Bool {
        estimatedCardsHeight > maximumCardAreaHeight
    }

    private var cardAreaHeight: CGFloat {
        if preferences.selectedPairs.isEmpty {
            return 112
        }

        return shouldScrollCards ? maximumCardAreaHeight : estimatedCardsHeight
    }

    private var panelHeight: CGFloat {
        chromeHeight + cardAreaHeight
    }

    private var maximumPanelHeight: CGFloat {
        let visibleHeight = currentWindow?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900
        return max(320, min(760, visibleHeight - 120))
    }

    private var chromeHeight: CGFloat {
        let toolbarHeight: CGFloat = 38
        let bannerHeight: CGFloat = shouldShowStatusBanner ? 44 : 0
        let footerHeight: CGFloat = 46
        let spacingCount: CGFloat = shouldShowStatusBanner ? 3 : 2
        return 32 + toolbarHeight + bannerHeight + footerHeight + (spacingCount * 12)
    }

    private func estimatedHeight(for card: CurrencyCardModel) -> CGFloat {
        expandedCardID == card.id ? 262 : 110
    }

    private func toolbarButtonLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }

    private func refreshIntervalTitle(for value: Int) -> String {
        switch value {
        case 0:
            String(localized: "关闭")
        case 5:
            String(localized: "5分钟")
        case 10:
            String(localized: "10分钟")
        case 30:
            String(localized: "30分钟")
        case 60:
            String(localized: "1小时")
        default:
            String(format: String(localized: "%d分钟"), value)
        }
    }

    private func resizePinnedWindowIfNeeded() {
        guard presentationMode == .pinned,
              let currentWindow else {
            return
        }

        let targetSize = NSSize(width: 424, height: panelHeight + 32)
        if currentWindow.contentLayoutRect.size != targetSize {
            currentWindow.setContentSize(targetSize)
        }
    }
}

private struct CurrencyCardView: View {
    let card: CurrencyCardModel
    let isFeatured: Bool
    let showsFlags: Bool
    let isExpanded: Bool
    @Binding var expandedCardID: String?

    @State private var selectedRange: CardTrendRange = .oneMonth
    @State private var baseAmountText = ""
    @State private var quoteAmountText = ""
    @State private var isSynchronizingConversion = false
    @State private var lastEditedField: ConversionField = .base
    @State private var selectedDetailMode: CardDetailMode = .trend
    @FocusState private var focusedField: ConversionField?

    private enum ConversionField {
        case base
        case quote
    }

    private enum CardDetailMode: String, CaseIterable, Identifiable {
        case trend
        case converter

        var id: String {
            rawValue
        }

        var title: LocalizedStringKey {
            switch self {
            case .trend:
                "趋势"
            case .converter:
                "换算"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isExpanded {
                expandedContent
            }

            if !collapsedMetaText.isEmpty {
                metaRow(text: collapsedMetaText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard canExpand, isExpanded == false else {
                return
            }

            expandCard()
        }
        .onAppear {
            resetConversionFields()
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                selectedDetailMode = .trend
                resetConversionFields()
                focusedField = nil
            } else {
                focusedField = nil
            }
        }
        .onChange(of: card.snapshot?.rate) { _, _ in
            if isExpanded {
                refreshConversionForCurrentFocus()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isExpanded)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if showsFlags {
                        Text("\(CurrencyCatalog.flag(for: card.pair.baseCode)) \(CurrencyCatalog.flag(for: card.pair.quoteCode))")
                            .font(.system(size: 15))
                    }

                    HStack(spacing: 6) {
                        Text(card.pair.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        if canExpand {
                            Button {
                                toggleExpanded()
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(card.subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(card.valueText)
                    .font(.system(size: card.snapshot == nil ? 18 : 26, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(card.valueColor)
                    .multilineTextAlignment(.trailing)

                if let changeText = card.changeText {
                    valueChip(text: changeText, color: card.changeColor)
                } else if let statusChipText = card.statusChipText {
                    valueChip(text: statusChipText, color: card.statusChipColor)
                }
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if canSwitchDetailMode {
            detailModePicker
                .transition(.opacity)
        }

        switch selectedContentMode {
        case .trend:
            if showsChartSection {
                chartSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        case .converter:
            if card.snapshot != nil {
                converterSection
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }

        detailFooter
            .transition(.opacity)
    }

    private var detailFooter: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(expandedMetaText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if selectedContentMode == .trend && showsChartSection {
                TrendRangePicker(selectedRange: $selectedRange)
            }
        }
    }

    private var chartSection: some View {
        TrendChartView(
            points: displayedChartPoints,
            lineColor: card.sparklineColor,
            placeholderText: chartPlaceholderText
        )
        .frame(height: 132)
    }

    @ViewBuilder
    private var converterSection: some View {
        HStack(spacing: 10) {
            converterField(
                title: card.pair.baseCode,
                text: converterBinding(for: .base),
                field: .base,
                alignment: .leading
            )

            Text("=")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            converterField(
                title: card.pair.quoteCode,
                text: converterBinding(for: .quote),
                field: .quote,
                alignment: .trailing
            )
        }
        .frame(height: 132, alignment: .center)
    }

    private func metaRow(text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var canExpand: Bool {
        card.snapshot != nil || card.historyPoints.count >= 2
    }

    private var displayedChartPoints: [TrendPoint] {
        card.chartPoints(for: selectedRange)
    }

    private var showsChartSection: Bool {
        displayedChartPoints.count >= 2 || card.snapshot != nil
    }

    private var canSwitchDetailMode: Bool {
        showsChartSection && card.snapshot != nil
    }

    private var selectedContentMode: CardDetailMode {
        if selectedDetailMode == .converter, card.snapshot != nil {
            return .converter
        }

        return .trend
    }

    private var collapsedMetaText: String {
        guard isExpanded == false else {
            return ""
        }

        return compactMetadataText
    }

    private var expandedMetaText: String {
        compactMetadataText
    }

    private var compactMetadataText: String {
        guard let snapshot = card.snapshot else {
            return ""
        }

        var segments: [String] = []
        if let effectiveDateText = snapshot.effectiveDateText, !effectiveDateText.isEmpty {
            segments.append(normalizedDateText(from: effectiveDateText))
        }
        segments.append(ExchangeFormatter.time.string(from: snapshot.updatedAt))
        if snapshot.isCached {
            segments.append(String(localized: "缓存"))
        }
        return segments.joined(separator: " · ")
    }

    private func normalizedDateText(from rawText: String) -> String {
        let parsedDate = SourceDateParser.isoDay(rawText)
            ?? SourceDateParser.cbrDay(rawText)
            ?? SourceDateParser.httpDay(rawText)

        guard let parsedDate else {
            return rawText
        }

        return Self.fullDateFormatter.string(from: parsedDate)
    }

    private var chartPlaceholderText: String {
        switch card.state {
        case .loading:
            return String(localized: "等待图表数据")
        case .failed:
            return String(localized: "暂时没有图表数据")
        case .ready, .stale:
            return String(localized: "图表数据不足")
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(isFeatured ? 0.04 : 0.018), radius: isFeatured ? 6 : 2, y: isFeatured ? 2 : 1)
    }

    private var borderColor: Color {
        if isFeatured {
            return Color.accentColor.opacity(0.28)
        }

        switch card.state {
        case .loading:
            return Color.secondary.opacity(0.16)
        case .failed:
            return Color(red: 0.74, green: 0.20, blue: 0.18).opacity(0.18)
        case .stale:
            return Color(red: 0.78, green: 0.50, blue: 0.11).opacity(0.18)
        case .ready:
            return Color.black.opacity(0.06)
        }
    }

    private func valueChip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func converterField(
        title: String,
        text: Binding<String>,
        field: ConversionField,
        alignment: Alignment
    ) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .focused($focusedField, equals: field)
                .onTapGesture {
                    focusedField = field
                    lastEditedField = field
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: alignment)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private var detailModePicker: some View {
        HStack(spacing: 4) {
            ForEach(CardDetailMode.allCases) { mode in
                Button {
                    selectedDetailMode = mode
                    if mode == .converter {
                        focusedField = .base
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selectedContentMode == mode ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedContentMode == mode ? Color(nsColor: .windowBackgroundColor) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.86))
        )
    }

    private func converterBinding(for field: ConversionField) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .base:
                    return baseAmountText
                case .quote:
                    return quoteAmountText
                }
            },
            set: { newValue in
                handleConversionChange(newValue, editedField: field)
            }
        )
    }

    private func resetConversionFields() {
        guard let snapshot = card.snapshot else {
            baseAmountText = ""
            quoteAmountText = ""
            return
        }

        lastEditedField = .base
        synchronizeFromBase(Double(card.pair.baseAmount), snapshot: snapshot)
    }

    private func handleConversionChange(_ newValue: String, editedField: ConversionField) {
        if isSynchronizingConversion {
            setText(newValue, for: editedField)
            return
        }

        setText(newValue, for: editedField)
        lastEditedField = editedField

        guard isExpanded, let snapshot = card.snapshot else {
            return
        }

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            setCounterpartText("", for: editedField)
            return
        }

        guard let value = parseAmount(trimmed) else {
            return
        }

        switch editedField {
        case .base:
            let quoteAmount = (value / Double(card.pair.baseAmount)) * snapshot.rate
            setCounterpartText(formattedAmount(quoteAmount), for: editedField)
        case .quote:
            guard snapshot.rate > 0 else {
                return
            }

            let baseAmount = (value / snapshot.rate) * Double(card.pair.baseAmount)
            setCounterpartText(formattedAmount(baseAmount), for: editedField)
        }
    }

    private func refreshConversionForCurrentFocus() {
        guard let snapshot = card.snapshot else {
            return
        }

        if lastEditedField == .quote, let quoteValue = parseAmount(quoteAmountText) {
            synchronizeFromQuote(quoteValue, snapshot: snapshot)
            return
        }

        if let baseValue = parseAmount(baseAmountText) {
            synchronizeFromBase(baseValue, snapshot: snapshot)
            return
        }

        synchronizeFromBase(Double(card.pair.baseAmount), snapshot: snapshot)
    }

    private func synchronizeFromBase(_ baseAmount: Double, snapshot: CurrencySnapshot) {
        let quoteAmount = (baseAmount / Double(card.pair.baseAmount)) * snapshot.rate

        isSynchronizingConversion = true
        baseAmountText = formattedAmount(baseAmount)
        quoteAmountText = formattedAmount(quoteAmount)
        isSynchronizingConversion = false
    }

    private func synchronizeFromQuote(_ quoteAmount: Double, snapshot: CurrencySnapshot) {
        guard snapshot.rate > 0 else {
            return
        }

        let baseAmount = (quoteAmount / snapshot.rate) * Double(card.pair.baseAmount)

        isSynchronizingConversion = true
        quoteAmountText = formattedAmount(quoteAmount)
        baseAmountText = formattedAmount(baseAmount)
        isSynchronizingConversion = false
    }

    private func toggleExpanded() {
        if isExpanded {
            expandedCardID = nil
            return
        }

        expandCard()
    }

    private func expandCard() {
        expandedCardID = card.id
        resetConversionFields()
        focusedField = .base
    }

    private func parseAmount(_ text: String) -> Double? {
        guard let parsed = MoneyParsing.parse(text) else {
            return nil
        }

        let resolvedAmount: Decimal
        switch parsed.amount {
        case .resolved(let value):
            resolvedAmount = value
        case .ambiguous(_, let options):
            guard let preferredValue = options.first?.value else {
                return nil
            }
            resolvedAmount = preferredValue
        }

        return NSDecimalNumber(decimal: resolvedAmount).doubleValue
    }

    private func setText(_ value: String, for field: ConversionField) {
        switch field {
        case .base:
            baseAmountText = value
        case .quote:
            quoteAmountText = value
        }
    }

    private func setCounterpartText(_ value: String, for editedField: ConversionField) {
        isSynchronizingConversion = true
        switch editedField {
        case .base:
            quoteAmountText = value
        case .quote:
            baseAmountText = value
        }
        isSynchronizingConversion = false
    }

    private func formattedAmount(_ value: Double) -> String {
        Self.converterFormatter.string(from: value as NSNumber) ?? String(format: "%.4f", value)
    }

    private static let converterFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct TrendRangePicker: View {
    @Binding var selectedRange: CardTrendRange

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CardTrendRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedRange == range ? Color.white : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedRange == range ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct TrendChartView: View {
    let points: [TrendPoint]
    let lineColor: Color
    let placeholderText: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.20, green: 0.22, blue: 0.29),
                            Color(red: 0.16, green: 0.18, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)

            if points.count >= 2 {
                chartContent
            } else {
                Text(placeholderText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
    }

    private var chartContent: some View {
        let values = points.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let latestDate = points.last?.timestamp ?? .now

        return GeometryReader { proxy in
            let plotInsets = EdgeInsets(top: 10, leading: 28, bottom: 20, trailing: 28)

            ZStack {
                chartGrid
                    .padding(.top, plotInsets.top)
                    .padding(.leading, plotInsets.leading)
                    .padding(.bottom, plotInsets.bottom)
                    .padding(.trailing, plotInsets.trailing)

                TrendAreaShape(values: values)
                    .fill(
                        LinearGradient(
                            colors: [
                                lineColor.opacity(0.14),
                                lineColor.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.top, plotInsets.top)
                    .padding(.leading, plotInsets.leading)
                    .padding(.bottom, plotInsets.bottom)
                    .padding(.trailing, plotInsets.trailing)

                TrendLineShape(values: values)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .padding(.top, plotInsets.top)
                    .padding(.leading, plotInsets.leading)
                    .padding(.bottom, plotInsets.bottom)
                    .padding(.trailing, plotInsets.trailing)

                VStack {
                    HStack {
                        Text(Self.axisFormatter.string(from: maxValue as NSNumber) ?? String(format: "%.3f", maxValue))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text(Self.axisFormatter.string(from: minValue as NSNumber) ?? String(format: "%.3f", minValue))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                        Spacer()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(Self.dateFormatter.string(from: latestDate))
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var chartGrid: some View {
        GeometryReader { proxy in
            Path { path in
                let horizontalOffsets = stride(from: 0, through: 3, by: 1).map { CGFloat($0) / 3 }
                let verticalOffsets = stride(from: 0, through: 4, by: 1).map { CGFloat($0) / 4 }

                for offset in horizontalOffsets {
                    let y = proxy.size.height * offset
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }

                for offset in verticalOffsets {
                    let x = proxy.size.width * offset
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
            }
            .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 0.8))
        }
    }

    private static let axisFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct TrendLineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2 else {
            return Path()
        }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 0.000_1)
        let stepX = rect.width / CGFloat(values.count - 1)

        var path = Path()

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (value - minValue) / range
            let y = rect.maxY - (CGFloat(normalized) * rect.height)

            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

private struct TrendAreaShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count >= 2 else {
            return Path()
        }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 0.000_1)
        let stepX = rect.width / CGFloat(values.count - 1)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (value - minValue) / range
            let y = rect.maxY - (CGFloat(normalized) * rect.height)
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    let preferences = PreferencesStore()
    let credentialStore = EnhancedSourceCredentialStore()
    let service = ExchangeRateService()
    let store = ExchangeRateStore()
    let viewModel = ExchangePanelViewModel(preferences: preferences, credentialStore: credentialStore, service: service, previewState: .sample)
    let promptPanel = LightweightPromptPanel()
    let coordinator = ConversionCoordinator(
        preferences: preferences,
        credentialStore: credentialStore,
        service: service,
        store: store,
        promptPanel: promptPanel,
        clipboardWriter: ClipboardWriter(),
        liveLogHandler: { _, _ in }
    )
    let globalShortcutHandler = GlobalShortcutHandler(
        preferences: preferences,
        coordinator: coordinator,
        popupPresenter: promptPanel,
        logHandler: { _, _ in }
    )
    let settingsController = SettingsWindowController(
        preferences: preferences,
        credentialStore: credentialStore,
        launchController: LaunchAtLoginController(),
        viewModel: viewModel,
        service: service,
        dockVisibilityController: DockVisibilityController(logHandler: { _, _ in }),
        globalShortcutHandler: globalShortcutHandler
    )
    let panelController = PanelWindowController(viewModel: viewModel)
    ContentView(
        viewModel: viewModel,
        preferences: preferences,
        settingsWindowController: settingsController,
        panelWindowController: panelController,
        autoBootstrap: false,
        presentationMode: .menuBar
    )
}
