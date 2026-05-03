//
//  ContentView.swift
//  Currency Tracker
//
//  Created by Thomas Tao on 4/10/26.
//

import AppKit
import SwiftUI

private enum PanelContentMode: Equatable {
    case rates
    case converter
}

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
    @State private var windowContentSize: CGSize?
    @State private var panelContentMode: PanelContentMode = .rates
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            panelHeader
            compactStatusBanner
            panelContent
            footer
        }
        .padding(16)
        .frame(
            minWidth: 408,
            idealWidth: 408,
            maxWidth: 560,
            minHeight: minimumPanelHeight,
            idealHeight: panelHeight,
            maxHeight: maximumPanelHeight,
            alignment: .top
        )
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
                    windowContentSize = $0?.contentLayoutRect.size
                    configureMenuBarWindow($0)
                    panelWindowController.registerMenuBarWindow($0)
                    resizePinnedWindowIfNeeded()
                },
                onResize: { size in
                    windowContentSize = size
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
        .onChange(of: preferences.selectedPairIDs) { _, newValue in
            if preferences.converterCurrenciesFollowSelectedPairs, newValue.isEmpty {
                panelContentMode = .rates
            }
        }
        .onChange(of: preferences.converterCurrenciesFollowSelectedPairs) { _, _ in
            if !canOpenConverter {
                panelContentMode = .rates
            }
        }
        .onChange(of: preferences.converterCurrencyCodes) { _, _ in
            if !canOpenConverter {
                panelContentMode = .rates
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
            .help(quickAddHelpText)
            .popover(isPresented: $isShowingQuickAddPanel, arrowEdge: .top) {
                if usesConverterQuickAdd {
                    QuickAddConverterCurrencyPopover(
                        preferences: preferences,
                        viewModel: viewModel,
                        onClose: { isShowingQuickAddPanel = false }
                    )
                } else {
                    QuickAddPairPopover(
                        preferences: preferences,
                        viewModel: viewModel,
                        onClose: { isShowingQuickAddPanel = false }
                    )
                }
            }

            Button {
                panelWindowController.togglePinnedPanel(from: currentWindow)
            } label: {
                toolbarButtonLabel(
                    systemName: panelWindowController.isPinned ? "pin.fill" : "pin",
                    isActive: panelWindowController.isPinned
                )
            }
            .buttonStyle(.plain)
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

                Section("货币显示") {
                    Menu("显示基数") {
                        ForEach(preferences.rateDisplayBaseAmountOptions, id: \.self) { value in
                            Button {
                                preferences.setRateDisplayBaseAmount(value)
                                viewModel.presentationDidChange()
                            } label: {
                                HStack {
                                    Text("\(value)")
                                    if preferences.rateDisplayBaseAmount == value {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Menu("小数位") {
                        ForEach(preferences.conversionFractionDigitOptions, id: \.self) { value in
                            Button {
                                preferences.setConversionFractionDigits(value)
                                viewModel.presentationDidChange()
                            } label: {
                                HStack {
                                    Text("\(value) 位")
                                    if preferences.conversionFractionDigits == value {
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

                    Button("汇率与换算页设置…") {
                        settingsWindowController.show(section: .rates)
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

    private func configureMenuBarWindow(_ window: NSWindow?) {
        guard presentationMode == .menuBar, let window else {
            return
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView?.superview?.wantsLayer = true
        window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        window.styleMask.remove(.resizable)
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 408, height: 320)
        window.maxSize = NSSize(width: 560, height: maximumPanelHeight)
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
    private var panelContent: some View {
        switch panelContentMode {
        case .rates:
            cardList
        case .converter:
            converterList
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
                    .fill(cardSurfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(subtleBorderColor, lineWidth: 1)
                    )
            )
            .frame(maxWidth: .infinity, minHeight: cardListMinimumHeight, maxHeight: cardAreaHeight, alignment: .topLeading)
        } else if shouldScrollCards {
            NativePanelScrollView {
                cardStack
                    .padding(.trailing, nativeScrollBarGutterWidth)
            }
            .padding(.trailing, -nativeScrollBarGutterWidth)
            .frame(
                maxWidth: .infinity,
                minHeight: cardListMinimumHeight,
                maxHeight: cardAreaHeight,
                alignment: .top
            )
        } else {
            cardStack
                .frame(maxWidth: .infinity, minHeight: cardListMinimumHeight, maxHeight: cardAreaHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private var converterList: some View {
        let converterView = PanelCurrencyConverterView(
            snapshots: viewModel.converterSnapshots,
            currencyCodes: converterCurrencyCodes,
            displayBaseAmount: preferences.rateDisplayBaseAmount,
            fractionDigits: preferences.conversionFractionDigits,
            showsFlags: preferences.showsFlags
        )

        if shouldScrollConverter {
            NativePanelScrollView {
                converterView
                    .padding(.trailing, nativeScrollBarGutterWidth)
            }
            .padding(.trailing, -nativeScrollBarGutterWidth)
            .frame(
                maxWidth: .infinity,
                minHeight: converterListMinimumHeight,
                maxHeight: converterAreaHeight,
                alignment: .top
            )
        } else {
            converterView
                .frame(maxWidth: .infinity, minHeight: converterListMinimumHeight, maxHeight: converterAreaHeight, alignment: .top)
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
                    expandedCardID: $expandedCardID,
                    onRefresh: {
                        Task {
                            await viewModel.refresh(trigger: .manual)
                        }
                    }
                )
            }
        }
        .padding(.bottom, cardStackBottomPadding)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(viewModel.footerTimestampText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                panelContentMode = panelContentMode == .rates ? .converter : .rates
                expandedCardID = nil
            } label: {
                Image(systemName: panelContentMode == .rates ? "arrow.left.arrow.right" : "list.bullet")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenConverter)
            .help(panelContentMode == .rates ? "打开换算界面" : "返回汇率列表")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(footerSurfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(subtleBorderColor.opacity(0.8), lineWidth: 1)
                )
        )
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(panelSurfaceColor)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(panelBorderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 18, y: 8)
    }

    private var shouldShowStatusBanner: Bool {
        if preferences.selectedPairs.isEmpty {
            return true
        }

        return viewModel.statusSymbolName.contains("exclamationmark") || viewModel.cards.contains { $0.state != .ready }
    }

    private var maximumContentAreaHeight: CGFloat {
        max(112, panelHeightLimit - chromeHeight)
    }

    private var estimatedCardsHeight: CGFloat {
        let total = viewModel.cards.reduce(CGFloat.zero) { partialResult, card in
            partialResult + estimatedHeight(for: card)
        }

        return total + CGFloat(max(0, viewModel.cards.count - 1)) * 12 + cardStackBottomPadding
    }

    private var shouldScrollCards: Bool {
        estimatedCardsHeight > maximumContentAreaHeight
    }

    private var cardAreaHeight: CGFloat {
        if preferences.selectedPairs.isEmpty {
            return 112
        }

        return shouldScrollCards ? maximumContentAreaHeight : estimatedCardsHeight
    }

    private var converterCurrencyCodes: [String] {
        preferences.effectiveConverterCurrencyCodes
    }

    private var estimatedConverterHeight: CGFloat {
        if converterCurrencyCodes.isEmpty {
            return 112
        }

        return 12 + CGFloat(converterCurrencyCodes.count) * 62 + CGFloat(max(0, converterCurrencyCodes.count - 1)) * 10 + 34
    }

    private var shouldScrollConverter: Bool {
        estimatedConverterHeight > maximumContentAreaHeight
    }

    private var converterAreaHeight: CGFloat {
        if converterCurrencyCodes.isEmpty {
            return 112
        }

        return shouldScrollConverter ? maximumContentAreaHeight : estimatedConverterHeight
    }

    private var converterListMinimumHeight: CGFloat {
        presentationMode == .pinned ? 160 : min(converterAreaHeight, maximumContentAreaHeight)
    }

    private var contentAreaHeight: CGFloat {
        switch panelContentMode {
        case .rates:
            cardAreaHeight
        case .converter:
            converterAreaHeight
        }
    }

    private var panelHeight: CGFloat {
        chromeHeight + contentAreaHeight
    }

    private var maximumPanelHeight: CGFloat {
        let visibleHeight = currentWindow?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 900
        return max(320, min(760, visibleHeight - 120))
    }

    private var minimumPanelHeight: CGFloat {
        presentationMode == .pinned ? pinnedMinimumPanelHeight : min(panelHeight, maximumPanelHeight)
    }

    private var panelHeightLimit: CGFloat {
        guard presentationMode == .pinned,
              let contentHeight = windowContentSize?.height,
              contentHeight > 0 else {
            return maximumPanelHeight
        }

        return min(max(contentHeight, pinnedMinimumPanelHeight), maximumPanelHeight)
    }

    private var chromeHeight: CGFloat {
        let toolbarHeight: CGFloat = 38
        let bannerHeight: CGFloat = shouldShowStatusBanner ? 44 : 0
        let footerHeight: CGFloat = 34
        let spacingCount: CGFloat = shouldShowStatusBanner ? 3 : 2
        return 32 + toolbarHeight + bannerHeight + footerHeight + (spacingCount * 12)
    }

    private var cardStackBottomPadding: CGFloat {
        14
    }

    private var cardListMinimumHeight: CGFloat {
        presentationMode == .pinned ? 112 : cardAreaHeight
    }

    private var pinnedMinimumPanelHeight: CGFloat {
        320
    }

    private var canOpenConverter: Bool {
        preferences.converterCurrenciesFollowSelectedPairs
            ? !preferences.selectedPairs.isEmpty
            : true
    }

    private var usesConverterQuickAdd: Bool {
        panelContentMode == .converter && preferences.converterCurrenciesFollowSelectedPairs == false
    }

    private var quickAddHelpText: String {
        usesConverterQuickAdd ? String(localized: "快速添加换算币种") : String(localized: "快速添加货币对")
    }

    private var nativeScrollBarGutterWidth: CGFloat {
        13
    }

    private func estimatedHeight(for card: CurrencyCardModel) -> CGFloat {
        expandedCardID == card.id ? 262 : 110
    }

    private func toolbarButtonLabel(systemName: String, isActive: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.15) : toolbarButtonSurfaceColor)
            )
            .overlay(
                Circle()
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.32) : subtleBorderColor, lineWidth: 1)
            )
    }

    private var panelSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.095, green: 0.105, blue: 0.125)
            : Color(red: 0.948, green: 0.956, blue: 0.968)
    }

    private var cardSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.155, blue: 0.180)
            : Color.white
    }

    private var footerSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.130, green: 0.140, blue: 0.162)
            : Color(red: 0.985, green: 0.988, blue: 0.992)
    }

    private var toolbarButtonSurfaceColor: Color {
        colorScheme == .dark
            ? Color(red: 0.155, green: 0.165, blue: 0.190)
            : Color.white
    }

    private var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.09)
    }

    private var subtleBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.075)
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
        guard panelWindowController.isPinned,
              let currentWindow,
              currentWindow.styleMask.contains(.resizable) == false else {
            return
        }

        let targetSize = NSSize(width: 408, height: panelHeight)
        if currentWindow.contentLayoutRect.size != targetSize {
            currentWindow.setContentSize(targetSize)
        }
    }
}

private struct NativePanelScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 1)
        scrollView.verticalScroller?.controlSize = .small

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        context.coordinator.hostingView = hostingView

        scrollView.documentView = hostingView
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content
        context.coordinator.hostingView?.invalidateIntrinsicContentSize()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 1)
        scrollView.verticalScroller?.controlSize = .small
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}

private struct PanelCurrencyConverterView: View {
    let snapshots: [CurrencySnapshot]
    let currencyCodes: [String]
    let displayBaseAmount: Int
    let fractionDigits: Int
    let showsFlags: Bool

    @State private var inputTexts: [String: String] = [:]
    @State private var userEnteredTexts: [String: String] = [:]
    @State private var activeCode: String?
    @State private var isSynchronizing = false
    @FocusState private var focusedCode: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if currencyCodes.isEmpty {
                emptyState
            } else {
                ForEach(currencyCodes, id: \.self) { code in
                    converterRow(for: code)
                }

                if !unreachableCodes.isEmpty {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(String(format: String(localized: "缺少 %@ 的汇率路径"), unreachableCodes.joined(separator: "、")))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color(red: 0.70, green: 0.35, blue: 0.05))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.98, green: 0.93, blue: 0.84))
                    )
                }
            }
        }
        .onAppear {
            initializeIfNeeded()
        }
        .onChange(of: currencyCodes) { _, _ in
            reconcileInputs()
        }
        .onChange(of: rateSignature) { _, _ in
            recalculateFromActive()
        }
        .onChange(of: fractionDigits) { _, _ in
            recalculateFromActive()
        }
        .onChange(of: displayBaseAmount) { _, _ in
            if activeCode == nil || activeTextIsEmpty {
                initializeWithDefaultAmount()
            } else {
                recalculateFromActive()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有可换算的货币")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("点击右上角 + 添加换算币种，或在设置里维护换算页列表。")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(rowBackground(isActive: false))
    }

    private var graph: CurrencyConversionGraph {
        CurrencyConversionGraph(snapshots: snapshots)
    }

    private var rateSignature: String {
        snapshots.map { snapshot in
            "\(snapshot.id):\(snapshot.rate):\(snapshot.updatedAt.timeIntervalSince1970)"
        }
        .joined(separator: "|")
    }

    private var activeTextIsEmpty: Bool {
        guard let activeCode else {
            return true
        }

        return (inputTexts[activeCode] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unreachableCodes: [String] {
        guard let activeCode,
              let sourceText = inputTexts[activeCode],
              AmountInputParsing.parseDecimal(sourceText) != nil else {
            return []
        }

        let multipliers = graph.conversionMultipliers(from: activeCode)
        return currencyCodes.filter { $0 != activeCode && multipliers[$0] == nil }
    }

    private func converterRow(for code: String) -> some View {
        HStack(spacing: 12) {
            if showsFlags {
                Text(CurrencyCatalog.flag(for: code))
                    .font(.system(size: 22))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.70))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(code)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(CurrencyCatalog.name(for: code))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            TextField("0", text: binding(for: code))
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.trailing)
                .focused($focusedCode, equals: code)
                .onTapGesture {
                    activate(code)
                }
                .frame(minWidth: 116, maxWidth: 190, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(rowBackground(isActive: isRowActive(code)))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            activate(code)
            focusedCode = code
        }
    }

    private func rowBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(rowFillColor(isActive: isActive))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.34) : rowBorderColor, lineWidth: 1)
            )
    }

    private func rowFillColor(isActive: Bool) -> Color {
        if colorScheme == .dark {
            return isActive ? Color(red: 0.175, green: 0.190, blue: 0.230) : Color(red: 0.138, green: 0.148, blue: 0.172)
        }

        return isActive ? Color(red: 0.972, green: 0.982, blue: 1.0) : Color.white
    }

    private var rowBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.075)
    }

    private func binding(for code: String) -> Binding<String> {
        Binding(
            get: {
                inputTexts[code] ?? ""
            },
            set: { newValue in
                handleInputChange(newValue, sourceCode: code)
            }
        )
    }

    private func initializeIfNeeded() {
        guard activeCode == nil || currencyCodes.contains(activeCode ?? "") == false else {
            recalculateFromActive()
            return
        }

        initializeWithDefaultAmount()
    }

    private func initializeWithDefaultAmount() {
        guard let firstCode = currencyCodes.first else {
            inputTexts = [:]
            userEnteredTexts = [:]
            activeCode = nil
            return
        }

        let defaultText = "\(CurrencyDisplayFormatting.normalizedDisplayBaseAmount(displayBaseAmount))"
        inputTexts[firstCode] = defaultText
        userEnteredTexts[firstCode] = defaultText
        activeCode = firstCode
        focusedCode = firstCode
        synchronize(sourceCode: firstCode, sourceText: defaultText)
    }

    private func reconcileInputs() {
        let validCodes = Set(currencyCodes)
        inputTexts = inputTexts.filter { validCodes.contains($0.key) }
        userEnteredTexts = userEnteredTexts.filter { validCodes.contains($0.key) }

        if let activeCode, validCodes.contains(activeCode) {
            recalculateFromActive()
        } else {
            initializeWithDefaultAmount()
        }
    }

    private func recalculateFromActive() {
        guard let activeCode else {
            initializeWithDefaultAmount()
            return
        }

        let sourceText = inputTexts[activeCode] ?? ""
        synchronize(sourceCode: activeCode, sourceText: sourceText)
    }

    private func activate(_ code: String) {
        guard (inputTexts[code] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let defaultText = "\(CurrencyDisplayFormatting.normalizedDisplayBaseAmount(displayBaseAmount))"
        inputTexts[code] = defaultText
        userEnteredTexts[code] = defaultText
        activeCode = code
        synchronize(sourceCode: code, sourceText: defaultText)
    }

    private func handleInputChange(_ newValue: String, sourceCode: String) {
        inputTexts[sourceCode] = newValue
        guard !isSynchronizing else {
            return
        }

        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userEnteredTexts.removeValue(forKey: sourceCode)
        } else {
            userEnteredTexts[sourceCode] = newValue
        }
        activeCode = sourceCode
        synchronize(sourceCode: sourceCode, sourceText: newValue)
    }

    private func synchronize(sourceCode: String, sourceText: String) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearCounterpartTexts(sourceCode: sourceCode)
            return
        }

        guard let amount = AmountInputParsing.parseDecimal(trimmed) else {
            clearCounterpartTexts(sourceCode: sourceCode)
            return
        }

        let sourceAmount = NSDecimalNumber(decimal: amount).doubleValue
        let multipliers = graph.conversionMultipliers(from: sourceCode)

        isSynchronizing = true
        for code in currencyCodes where code != sourceCode {
            if let multiplier = multipliers[code] {
                inputTexts[code] = displayText(for: code, amount: sourceAmount * multiplier)
            } else {
                inputTexts[code] = ""
            }
        }
        isSynchronizing = false
    }

    private func clearCounterpartTexts(sourceCode: String) {
        isSynchronizing = true
        for code in currencyCodes where code != sourceCode {
            inputTexts[code] = ""
        }
        isSynchronizing = false
    }

    private func isRowActive(_ code: String) -> Bool {
        if let focusedCode {
            return focusedCode == code
        }

        return activeCode == code
    }

    private func displayText(for code: String, amount: Double) -> String {
        if let enteredText = userEnteredTexts[code],
           shouldPreserveUserEnteredText(enteredText, for: amount) {
            return enteredText
        }

        return CurrencyDisplayFormatting.plainNumber(amount, fractionDigits: fractionDigits)
    }

    private func shouldPreserveUserEnteredText(_ text: String, for amount: Double) -> Bool {
        guard let enteredAmount = AmountInputParsing.parseDecimal(text) else {
            return false
        }

        let enteredValue = NSDecimalNumber(decimal: enteredAmount).doubleValue
        guard enteredValue.isFinite, amount.isFinite else {
            return false
        }

        return abs(enteredValue - amount) < 0.000_000_5
    }
}

private struct CurrencyCardView: View {
    let card: CurrencyCardModel
    let isFeatured: Bool
    let showsFlags: Bool
    let isExpanded: Bool
    @Binding var expandedCardID: String?
    let onRefresh: () -> Void
    @Environment(\.colorScheme) private var colorScheme

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
                "历史"
            case .converter:
                "换算"
            }
        }

        var symbolName: String {
            switch self {
            case .trend:
                "chart.line.uptrend.xyaxis"
            case .converter:
                "arrow.left.arrow.right"
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
        .contextMenu {
            Button("复制货币对") {
                copyText(card.compactPairLabel)
            }
            if let snapshot = card.snapshot {
                Button("复制汇率") {
                    copyText("\(card.compactPairLabel) \(card.valueText)")
                }
                Button("复制数据源") {
                    copyText(snapshot.source.displayName)
                }
            }
            Divider()
            Button("刷新") {
                onRefresh()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isExpanded)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsFlags {
                Text("\(CurrencyCatalog.flag(for: card.pair.baseCode))\n\(CurrencyCatalog.flag(for: card.pair.quoteCode))")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .frame(width: 28, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.82))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(card.compactPairLabel)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if canExpand {
                            Button {
                                toggleExpanded()
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(isExpanded ? "收起详情" : "展开详情")
                        }
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 12)

                    Text(card.valueText)
                        .font(.system(size: card.snapshot == nil ? 18 : 26, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(card.valueColor)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)
                        .frame(minWidth: 150, idealWidth: 170, maxWidth: 190, alignment: .trailing)
                        .layoutPriority(2)
                }

                HStack(alignment: .center, spacing: 8) {
                    Text(pairSecondaryText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    Spacer(minLength: 8)

                    if let changeText = card.changeText {
                        valueChip(text: changeText, color: card.changeColor)
                            .layoutPriority(2)
                    } else if let statusChipText = card.statusChipText {
                        valueChip(text: statusChipText, color: card.statusChipColor)
                            .layoutPriority(2)
                    }

                    if card.state == .failed {
                        Button {
                            onRefresh()
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .layoutPriority(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        let chartSummary = selectedContentMode == .trend ? chartSummaryText : ""
        return [compactMetadataText, chartSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var compactMetadataText: String {
        guard let snapshot = card.snapshot else {
            return ""
        }

        var segments: [String] = []
        if let effectiveDateText = snapshot.effectiveDateText, !effectiveDateText.isEmpty {
            segments.append(normalizedDateText(from: effectiveDateText))
        }
        segments.append(snapshot.source.displayName)
        segments.append(ExchangeFormatter.time.string(from: snapshot.updatedAt))
        if snapshot.isCached {
            segments.append(String(localized: "缓存"))
        }
        return segments.joined(separator: " · ")
    }

    private var chartSummaryText: String {
        let points = displayedChartPoints
        guard let first = points.first?.value,
              let last = points.last?.value,
              first > 0,
              points.count >= 2 else {
            return ""
        }

        let delta = last - first
        let percent = delta / first * 100
        let prefix = percent >= 0 ? "+" : ""
        return String(format: String(localized: "区间变化 %@%.2f%%"), prefix, percent)
    }

    private var pairSecondaryText: String {
        return "\(card.pair.displayName) · \(card.subtitle)"
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
            .fill(cardFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardSheenColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(cardShadowOpacity), radius: isFeatured ? 13 : 8, y: isFeatured ? 7 : 4)
    }

    private var cardFillColor: Color {
        if colorScheme == .dark {
            return isFeatured
                ? Color(red: 0.165, green: 0.178, blue: 0.210)
                : Color(red: 0.138, green: 0.148, blue: 0.172)
        }

        return isFeatured
            ? Color(red: 0.988, green: 0.992, blue: 1.0)
            : Color.white
    }

    private var cardSheenColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isFeatured ? 0.055 : 0.025)
        }

        return Color.white.opacity(isFeatured ? 0.30 : 0.12)
    }

    private var cardShadowOpacity: Double {
        if colorScheme == .dark {
            return isFeatured ? 0.38 : 0.24
        }

        return isFeatured ? 0.14 : 0.09
    }

    private var borderColor: Color {
        if isFeatured {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.42 : 0.34)
        }

        switch card.state {
        case .loading:
            return Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.18)
        case .failed:
            return Color(red: 0.74, green: 0.20, blue: 0.18).opacity(0.24)
        case .stale:
            return Color(red: 0.78, green: 0.50, blue: 0.11).opacity(0.24)
        case .ready:
            return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.085)
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
                .fill(colorScheme == .dark ? Color.black.opacity(0.18) : Color(red: 0.955, green: 0.962, blue: 0.974))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
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
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 10, weight: .bold))
                        Text(mode.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(selectedContentMode == mode ? Color.primary : Color.secondary)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedContentMode == mode ? segmentedSelectionColor : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selectedContentMode == mode ? segmentedSelectionBorderColor : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(segmentedControlBackgroundColor)
        )
    }

    private var segmentedControlBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.24)
            : Color(red: 0.888, green: 0.902, blue: 0.922)
    }

    private var segmentedSelectionColor: Color {
        colorScheme == .dark
            ? Color(red: 0.205, green: 0.220, blue: 0.260)
            : Color.white
    }

    private var segmentedSelectionBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
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
        synchronizeFromBase(Double(card.displayBaseAmount), snapshot: snapshot)
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
            setCounterpartText("", for: editedField)
            return
        }

        switch editedField {
        case .base:
            let quoteAmount = value * unitRate(from: snapshot)
            setCounterpartText(formattedAmount(quoteAmount), for: editedField)
        case .quote:
            let unitRate = unitRate(from: snapshot)
            guard unitRate > 0 else {
                return
            }

            let baseAmount = value / unitRate
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
        let quoteAmount = baseAmount * unitRate(from: snapshot)

        isSynchronizingConversion = true
        baseAmountText = wholeAmountTextIfPossible(baseAmount)
        quoteAmountText = formattedAmount(quoteAmount)
        isSynchronizingConversion = false
    }

    private func synchronizeFromQuote(_ quoteAmount: Double, snapshot: CurrencySnapshot) {
        let unitRate = unitRate(from: snapshot)
        guard unitRate > 0 else {
            return
        }

        let baseAmount = quoteAmount / unitRate

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
        guard let amount = AmountInputParsing.parseDecimal(text) else {
            return nil
        }

        return NSDecimalNumber(decimal: amount).doubleValue
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
        CurrencyDisplayFormatting.plainNumber(value, fractionDigits: card.fractionDigits)
    }

    private func wholeAmountTextIfPossible(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return formattedAmount(value)
    }

    private func unitRate(from snapshot: CurrencySnapshot) -> Double {
        snapshot.rate / Double(max(card.pair.baseAmount, 1))
    }

    private func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(chartBackground)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(chartBorderColor, lineWidth: 1)

            if points.count >= 2 {
                chartContent
            } else {
                Text(placeholderText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(axisTextColor.opacity(0.82))
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
                            .foregroundStyle(axisTextColor)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text(Self.axisFormatter.string(from: minValue as NSNumber) ?? String(format: "%.3f", minValue))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(axisTextColor.opacity(0.90))
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
                    .foregroundStyle(axisTextColor.opacity(0.88))
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
            .stroke(gridColor, style: StrokeStyle(lineWidth: 0.8))
        }
    }

    private var chartBackground: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.145, green: 0.158, blue: 0.192),
                    Color(red: 0.110, green: 0.122, blue: 0.150)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.965, green: 0.973, blue: 0.988),
                Color(red: 0.938, green: 0.950, blue: 0.972)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var chartBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }

    private var axisTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.76) : Color.secondary
    }

    private var gridColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.075)
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
        globalShortcutHandler: globalShortcutHandler,
        softwareUpdateWindowController: SoftwareUpdateWindowController()
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
