//
//  SettingsView.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import AppKit
import ApplicationServices
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum SettingsSection: String, CaseIterable, Hashable, Sendable {
    case welcome
    case general
    case language
    case rates
    case profiles
    case alerts
    case refresh
    case dataSources
    case permissions
    case updates
    case diagnostics
    case system

    var title: LocalizedStringKey {
        switch self {
        case .welcome:
            "欢迎"
        case .general:
            "通用"
        case .language:
            "语言"
        case .rates:
            "汇率"
        case .profiles:
            "配置"
        case .alerts:
            "提醒"
        case .refresh:
            "刷新"
        case .dataSources:
            "数据源"
        case .permissions:
            "权限"
        case .updates:
            "更新"
        case .diagnostics:
            "诊断"
        case .system:
            "系统"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .welcome:
            "首次设置与使用建议"
        case .general:
            "基准货币与文本换算"
        case .language:
            "显示语言与区域"
        case .rates:
            "展示列表与新增汇率"
        case .profiles:
            "保存和切换工作流"
        case .alerts:
            "价格阈值通知"
        case .refresh:
            "自动更新行为"
        case .dataSources:
            "API key 与增强来源"
        case .permissions:
            "系统能力状态"
        case .updates:
            "版本与下载"
        case .diagnostics:
            "导出排障信息"
        case .system:
            "开机启动"
        }
    }

    var symbolName: String {
        switch self {
        case .welcome:
            "sparkles"
        case .general:
            "gearshape"
        case .language:
            "globe"
        case .rates:
            "list.bullet.rectangle"
        case .profiles:
            "square.stack.3d.up"
        case .alerts:
            "bell"
        case .refresh:
            "arrow.clockwise"
        case .dataSources:
            "key"
        case .permissions:
            "checkmark.shield"
        case .updates:
            "arrow.down.circle"
        case .diagnostics:
            "stethoscope"
        case .system:
            "power"
        }
    }
}

private enum SoftwareUpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case available(SoftwareUpdateInfo)
    case failed(String)
}

private struct SupportedAppLanguage: Identifiable {
    let code: String
    let nativeName: String

    var id: String {
        code
    }
}

struct SettingsView: View {
    let preferences: PreferencesStore
    let launchController: LaunchAtLoginController
    let viewModel: ExchangePanelViewModel
    let apiConfigurationViewModel: APIConfigurationViewModel
    let globalShortcutHandler: GlobalShortcutHandler
    let softwareUpdateWindowController: SoftwareUpdateWindowController
    let focusSection: SettingsSection?

    @Environment(\.colorScheme) private var colorScheme

    @State private var draftBaseCode = "USD"
    @State private var draftQuoteCode = "RUB"
    @State private var currencySearch = ""
    @State private var converterCurrencySearch = ""
    @State private var draftConverterCurrencyCode = "USD"
    @State private var draggedPairID: String?
    @State private var selectedSection: SettingsSection = .welcome
    @State private var isShowingAPIPrivacyDetails = false
    @State private var updateCheckState: SoftwareUpdateCheckState = .idle
    @State private var lastUpdateCheckDate: Date?
    @State private var profileNameDraft = ""
    @State private var alertPairID = ""
    @State private var alertDirection: RateAlertDirection = .above
    @State private var alertThresholdText = ""
    @State private var diagnosticExportMessage: String?
    @State private var languageSettingsMessage: String?

    private let detailTitlebarClearance: CGFloat = 36
    private let detailContentPadding: CGFloat = 24
    private let detailContentMaxWidth: CGFloat = 820

    private let supportedAppLanguages = [
        SupportedAppLanguage(code: "en", nativeName: "English"),
        SupportedAppLanguage(code: "zh-Hans", nativeName: "简体中文"),
        SupportedAppLanguage(code: "zh-Hant", nativeName: "繁體中文"),
        SupportedAppLanguage(code: "ru", nativeName: "Русский"),
        SupportedAppLanguage(code: "ja", nativeName: "日本語"),
        SupportedAppLanguage(code: "ko", nativeName: "한국어"),
        SupportedAppLanguage(code: "fr", nativeName: "Français"),
        SupportedAppLanguage(code: "de", nativeName: "Deutsch"),
        SupportedAppLanguage(code: "es", nativeName: "Español"),
        SupportedAppLanguage(code: "pt-BR", nativeName: "Português do Brasil"),
        SupportedAppLanguage(code: "it", nativeName: "Italiano")
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            settingsDivider

            detailPane
        }
        .frame(minWidth: 780, minHeight: 540, alignment: .topLeading)
        .background(windowBackground)
        .onAppear {
            syncDraftSelectionToSearchResults()
            syncConverterCurrencySelectionToSearchResults()
            apiConfigurationViewModel.reloadFromStore()
            applyFocusedSection()
        }
        .onChange(of: currencySearch) { _, _ in
            syncDraftSelectionToSearchResults()
        }
        .onChange(of: converterCurrencySearch) { _, _ in
            syncConverterCurrencySelectionToSearchResults()
        }
        .onChange(of: focusSection) { _, _ in
            applyFocusedSection()
        }
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: detailTitlebarClearance)
                .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    pageHeader
                    selectedPageContent
                }
                .frame(maxWidth: detailContentMaxWidth, alignment: .leading)
                .padding(.horizontal, detailContentPadding)
                .padding(.top, detailContentPadding)
                .padding(.bottom, detailContentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(detailPaneBackground)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            appHeader

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 4) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        sidebarButton(for: section)
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(.horizontal, 14)
        .padding(.top, detailTitlebarClearance + 14)
        .padding(.bottom, 18)
        .frame(width: 252)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
    }

    private var appHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text("Currency Tracker")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("管理汇率展示、刷新行为和系统级文本换算入口")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 6)
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: selectedSection.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(selectedSection.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(selectedSection.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(pageHeaderBackground)
    }

    @ViewBuilder
    private var selectedPageContent: some View {
        switch selectedSection {
        case .welcome:
            welcomeSection
        case .general:
            baseCurrencySection
            currencyDisplaySection
            menuBarDisplaySection
            textConversionShortcutSection
        case .language:
            languageSection
        case .rates:
            selectedPairsSection
            addPairSection
            converterCurrenciesSection
        case .profiles:
            profilesSection
        case .alerts:
            rateAlertsSection
        case .refresh:
            refreshBehaviorSection
        case .dataSources:
            apiConfigurationSection
        case .permissions:
            permissionsSection
        case .updates:
            softwareUpdateSection
        case .diagnostics:
            diagnosticsSection
        case .system:
            launchSection
        }
    }

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("用三步完成初始化")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            VStack(spacing: 10) {
                onboardingStep(
                    symbolName: "list.bullet.rectangle",
                    title: "添加常用货币对",
                    detail: preferences.selectedPairs.isEmpty
                        ? String(localized: "还没有添加汇率，先选择你每天要看的货币对。")
                        : String(format: String(localized: "已经添加 %d 个货币对。"), preferences.selectedPairs.count),
                    actionTitle: "管理汇率",
                    target: .rates
                )
                onboardingStep(
                    symbolName: "checkmark.shield",
                    title: "确认系统权限",
                    detail: String(localized: "全局快捷键和文本换算在部分应用中需要辅助功能权限。"),
                    actionTitle: "查看权限",
                    target: .permissions
                )
                onboardingStep(
                    symbolName: "key",
                    title: "按需启用增强数据源",
                    detail: String(localized: "没有 API key 也能使用公共来源；需要更高覆盖率时再添加自己的 key。"),
                    actionTitle: "数据源",
                    target: .dataSources
                )
            }
        }
        .padding(18)
        .background(sectionCardBackground)
    }

    private func onboardingStep(
        symbolName: String,
        title: LocalizedStringKey,
        detail: String,
        actionTitle: LocalizedStringKey,
        target: SettingsSection
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(actionTitle) {
                selectedSection = target
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func sidebarButton(for section: SettingsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            let isSelected = selectedSection == section
            HStack(spacing: 10) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.035))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
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
            .background(sidebarRowBackground(isSelected: isSelected))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.sidebar.\(section.rawValue)")
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("应用语言")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前语言")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(currentAppLanguageName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("打开语言与地区设置") {
                        openLanguageSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Text("Currency Tracker 使用 macOS 的“每个应用的语言”设置。修改后需要重启应用生效。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let languageSettingsMessage {
                    Text(languageSettingsMessage)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("支持的语言")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(supportedAppLanguages) { language in
                        HStack(spacing: 8) {
                            Text(language.nativeName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(language.code)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                    }
                }

                Text("在系统设置中为 Currency Tracker 添加语言覆盖，或调整首选语言顺序。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(sectionCardBackground)
        }
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

    private var menuBarDisplaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("菜单栏显示")

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择菜单栏中显示的信息密度")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("重点汇率来自面板中的第一张卡片。空间紧张时建议保持只显示图标。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker("菜单栏显示", selection: Binding(
                    get: { preferences.menuBarDisplayMode },
                    set: { preferences.setMenuBarDisplayMode($0) }
                )) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var currencyDisplaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("货币显示")

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("统一控制汇率基数和小数位")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("菜单栏、汇率卡片、换算器和选中文本换算结果会使用同一套显示规则。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 16) {
                    displayPreferencePicker(
                        title: "显示基数",
                        selection: Binding(
                            get: { preferences.rateDisplayBaseAmount },
                            set: {
                                preferences.setRateDisplayBaseAmount($0)
                                viewModel.presentationDidChange()
                            }
                        ),
                        options: preferences.rateDisplayBaseAmountOptions,
                        label: { "\($0)" }
                    )

                    displayPreferencePicker(
                        title: "小数位",
                        selection: Binding(
                            get: { preferences.conversionFractionDigits },
                            set: {
                                preferences.setConversionFractionDigits($0)
                                viewModel.presentationDidChange()
                            }
                        ),
                        options: preferences.conversionFractionDigitOptions,
                        label: { "\($0) 位" }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("配置 Profile")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TextField("Profile 名称", text: $profileNameDraft)
                        .textFieldStyle(.roundedBorder)

                    Button("保存当前配置") {
                        preferences.saveCurrentProfile(named: profileNameDraft)
                        profileNameDraft = ""
                        viewModel.refreshPolicyDidChange()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(preferences.selectedPairIDs.isEmpty && preferences.effectiveConverterCurrencyCodes.isEmpty)
                }

                if preferences.settingsProfiles.isEmpty {
                    Text("还没有保存 Profile。保存后可以在不同货币对列表、基准货币和刷新策略之间快速切换。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .windowBackgroundColor))
                        )
                } else {
                    VStack(spacing: 10) {
                        ForEach(preferences.settingsProfiles) { profile in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    Text(profileSummaryText(for: profile))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if preferences.activeProfileID == profile.id {
                                    Label("当前", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color(red: 0.09, green: 0.53, blue: 0.32))
                                }

                                Button("应用") {
                                    preferences.applyProfile(id: profile.id)
                                    Task {
                                        await viewModel.selectedPairsDidChange()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("删除") {
                                    preferences.deleteProfile(id: profile.id)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                        }
                    }
                }
            }
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var rateAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("汇率提醒")

            VStack(alignment: .leading, spacing: 14) {
                if preferences.selectedPairs.isEmpty {
                    Text("先添加货币对后才能创建提醒。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        Picker("货币对", selection: Binding(
                            get: { resolvedAlertPairID },
                            set: { alertPairID = $0 }
                        )) {
                            ForEach(preferences.selectedPairs) { pair in
                                Text(pair.compactLabel).tag(pair.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)

                        Picker("方向", selection: $alertDirection) {
                            ForEach(RateAlertDirection.allCases) { direction in
                                Text(direction.title).tag(direction)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)

                        TextField("阈值", text: $alertThresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        Button("添加提醒") {
                            if let threshold = Double(alertThresholdText.replacingOccurrences(of: ",", with: ".")) {
                                preferences.addRateAlert(pairID: resolvedAlertPairID, direction: alertDirection, threshold: threshold)
                                alertThresholdText = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(Double(alertThresholdText.replacingOccurrences(of: ",", with: ".")) == nil)
                    }
                }

                if preferences.rateAlerts.isEmpty {
                    Text("没有启用的汇率提醒。提醒触发后会请求系统通知权限，并在 12 小时内避免重复打扰。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(preferences.rateAlerts) { alert in
                            RateAlertRow(
                                alert: alert,
                                pair: PreferencesStore.pairForDisplay(id: alert.pairID),
                                onChange: { preferences.updateRateAlert($0) },
                                onDelete: { preferences.removeRateAlert(id: alert.id) }
                            )
                        }
                    }
                }
            }
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
                                Text(pairSubtitle(for: pair))
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

    private var converterCurrenciesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("换算页币种")
                Spacer()
                countBadge(preferences.effectiveConverterCurrencyCodes.count)
            }

            VStack(alignment: .leading, spacing: 14) {
                Toggle("跟随汇率列表", isOn: Binding(
                    get: { preferences.converterCurrenciesFollowSelectedPairs },
                    set: { isEnabled in
                        preferences.setConverterCurrenciesFollowSelectedPairs(isEnabled)
                        Task {
                            await viewModel.selectedPairsDidChange()
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                Text("勾选后换算页继续从已添加货币对中自动提取币种；取消勾选后可以单独维护换算页列表。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.converterCurrenciesFollowSelectedPairs {
                    linkedConverterCurrencyList
                } else {
                    independentConverterCurrencyList
                    addConverterCurrencyControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var linkedConverterCurrencyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前联动币种")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if preferences.effectiveConverterCurrencyCodes.isEmpty {
                Text("暂无联动币种")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                currencyCodeWrap(preferences.effectiveConverterCurrencyCodes)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var independentConverterCurrencyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已添加换算币种")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if preferences.converterCurrencyCodes.isEmpty {
                Text("还没有添加换算币种")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach(preferences.converterCurrencyCodes, id: \.self) { code in
                        converterCurrencyRow(for: code)
                    }
                }
            }
        }
    }

    private var addConverterCurrencyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加换算币种")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            TextField("搜索币种代码、中文名或英文名", text: $converterCurrencySearch)
                .textFieldStyle(.roundedBorder)

            if filteredConverterCurrencies.isEmpty {
                searchEmptyState
            } else {
                HStack(spacing: 10) {
                    Picker("换算币种", selection: Binding(
                        get: { resolvedDraftConverterCurrencyCode },
                        set: { draftConverterCurrencyCode = $0 }
                    )) {
                        ForEach(filteredConverterCurrencies) { currency in
                            Text("\(CurrencyCatalog.name(for: currency.code)) · \(currency.code)")
                                .tag(currency.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280)

                    Button("加入换算") {
                        preferences.addConverterCurrency(code: resolvedDraftConverterCurrencyCode)
                        Task {
                            await viewModel.selectedPairsDidChange()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(converterCurrencyAlreadySelected)

                    if converterCurrencyAlreadySelected {
                        Text("这个币种已经存在")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var apiConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("数据增强")

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择你正在使用的供应商，下方只显示已添加的数据源。")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

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
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }

                    Spacer()

                    Menu {
                        ForEach(apiConfigurationViewModel.availableKindsToAdd) { kind in
                            Button(kind.displayName) {
                                apiConfigurationViewModel.addProvider(kind)
                            }
                        }
                    } label: {
                        Label("添加 API 数据源", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .disabled(apiConfigurationViewModel.availableKindsToAdd.isEmpty)
                    .help(apiConfigurationViewModel.availableKindsToAdd.isEmpty ? "已添加所有支持的数据源" : "添加 API 数据源")
                }

                VStack(spacing: 10) {
                    ForEach(apiConfigurationViewModel.selectedKinds) { kind in
                        APIConfigurationRow(
                            field: apiConfigurationViewModel.field(for: kind),
                            onValueChange: { apiConfigurationViewModel.updateDraft($0, for: kind) },
                            onToggleReveal: { apiConfigurationViewModel.toggleReveal(for: kind) },
                            onPrimaryAction: {
                                await apiConfigurationViewModel.performPrimaryAction(for: kind)
                            }
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("自定义 API 模板")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text("模板支持 {base}、{quote}、{key} 占位符，JSON path 用来读取返回值中的汇率。")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            preferences.addCustomAPIProvider()
                        } label: {
                            Label("添加自定义 API", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if preferences.customAPIProviders.isEmpty {
                        Text("还没有自定义 API。内置来源无法覆盖某些币种时，可以添加兼容 JSON 的汇率接口。")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(preferences.customAPIProviders) { provider in
                                CustomAPIProviderRow(
                                    provider: provider,
                                    onChange: { preferences.updateCustomAPIProvider($0) },
                                    onDelete: { preferences.removeCustomAPIProvider(id: provider.id) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("权限状态")

            VStack(spacing: 10) {
                permissionRow(
                    symbolName: "checkmark.shield",
                    title: String(localized: "辅助功能"),
                    detail: String(localized: "全局快捷键读取选中文本和复制回退需要此权限。"),
                    isReady: AXIsProcessTrusted(),
                    actionTitle: "打开隐私设置",
                    action: openAccessibilitySettings
                )
                permissionRow(
                    symbolName: "keyboard",
                    title: String(localized: "全局快捷键"),
                    detail: shortcutPermissionDetail,
                    isReady: preferences.textConversionShortcut != nil,
                    actionTitle: "设置快捷键",
                    action: { selectedSection = .general }
                )
                permissionRow(
                    symbolName: "bell",
                    title: String(localized: "通知"),
                    detail: String(localized: "汇率提醒触发时会使用系统通知；首次触发会请求授权。"),
                    isReady: true,
                    actionTitle: "管理提醒",
                    action: { selectedSection = .alerts }
                )
                permissionRow(
                    symbolName: "power",
                    title: String(localized: "开机启动"),
                    detail: launchPermissionDetail,
                    isReady: launchController.isEnabled && !launchController.requiresApproval,
                    actionTitle: "启动设置",
                    action: { selectedSection = .system }
                )
            }
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private func permissionRow(
        symbolName: String,
        title: String,
        detail: String,
        isReady: Bool,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isReady ? Color(red: 0.09, green: 0.53, blue: 0.32) : Color(red: 0.78, green: 0.50, blue: 0.11))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill((isReady ? Color.green : Color.orange).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(actionTitle) {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("诊断导出")

            VStack(alignment: .leading, spacing: 14) {
                Text("导出的诊断报告只包含版本、系统、偏好摘要、数据源状态和最近日志，不包含 API key。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        exportDiagnostics()
                    } label: {
                        Label("导出诊断报告", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    if let diagnosticExportMessage {
                        Text(diagnosticExportMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(sectionCardBackground)
        }
    }

    private var softwareUpdateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("软件更新")

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    updateStatusIcon

                    VStack(alignment: .leading, spacing: 5) {
                        Text(String(format: String(localized: "当前版本 %@"), SoftwareUpdateChecker.currentVersion()))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))

                        Text(updateStatusText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let lastUpdateCheckDate {
                            Text(String(format: String(localized: "上次检查：%@"), ExchangeFormatter.time.string(from: lastUpdateCheckDate)))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                        }

                        if updateCheckState == .checking {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .controlSize(.small)
                                .tint(.accentColor)
                                .frame(maxWidth: 260)
                                .transition(.opacity)
                        }
                    }

                    Spacer(minLength: 16)

                    VStack(alignment: .trailing, spacing: 8) {
                        Button(updateCheckButtonTitle) {
                            Task {
                                await checkForUpdates()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updateCheckState == .checking)
                        .accessibilityIdentifier("settings.updates.check")

                        if let releaseURL = updateReleaseURL {
                            Button(updateDownloadButtonTitle) {
                                NSWorkspace.shared.open(releaseURL)
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                    }
                }

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动检查更新")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("启动时每天最多检查一次；发现新版本时会弹出更新窗口。")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { preferences.automaticUpdateChecksEnabled },
                        set: { preferences.setAutomaticUpdateChecksEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Text("应用会从 GitHub Releases 下载更新，并在确认后安装和重启。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
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

    private var updateStatusIcon: some View {
        ZStack {
            Circle()
                .fill(updateStatusTint.opacity(0.14))
            Image(systemName: updateStatusSymbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(updateStatusTint)
        }
        .frame(width: 44, height: 44)
    }

    private var updateStatusSymbolName: String {
        switch updateCheckState {
        case .idle:
            "arrow.down.circle"
        case .checking:
            "arrow.triangle.2.circlepath"
        case .upToDate:
            "checkmark.circle.fill"
        case .available:
            "sparkles"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var updateStatusTint: Color {
        switch updateCheckState {
        case .idle, .checking:
            .secondary
        case .upToDate:
            Color(red: 0.09, green: 0.53, blue: 0.32)
        case .available:
            Color.accentColor
        case .failed:
            Color(red: 0.74, green: 0.20, blue: 0.18)
        }
    }

    private var shortcutPermissionDetail: String {
        guard let shortcut = preferences.textConversionShortcut else {
            return String(localized: "尚未设置文本换算快捷键。")
        }

        return String(format: String(localized: "已设置 %@。"), shortcut.displayText)
    }

    private var launchPermissionDetail: String {
        if launchController.requiresApproval {
            return String(localized: "需要在系统设置中批准登录项。")
        }

        return launchController.isEnabled
            ? String(localized: "已启用开机启动。")
            : String(localized: "未启用开机启动。")
    }

    private var updateStatusText: String {
        switch updateCheckState {
        case .idle:
            return String(localized: "点击检查更新以获取 GitHub 上的最新版本。")
        case .checking:
            return String(localized: "正在检查 GitHub Releases…")
        case .upToDate(let version):
            return String(format: String(localized: "已是最新版本 %@"), version)
        case .available(let info):
            return String(format: String(localized: "发现新版本 %@"), info.version)
        case .failed(let message):
            return message
        }
    }

    private var updateReleaseURL: URL? {
        if case .available(let info) = updateCheckState {
            return info.releaseURL
        }

        return SoftwareUpdateChecker.releasesURL
    }

    private var updateDownloadButtonTitle: LocalizedStringKey {
        return "打开发布页面"
    }

    private var updateCheckButtonTitle: LocalizedStringKey {
        updateCheckState == .checking ? "正在检查" : "检查更新"
    }

    @MainActor
    private func checkForUpdates() async {
        guard updateCheckState != .checking else {
            return
        }

        updateCheckState = .checking

        do {
            let latestInfo = try await SoftwareUpdateChecker.fetchLatestRelease()
            lastUpdateCheckDate = .now
            if latestInfo.isNewer(than: SoftwareUpdateChecker.currentVersion()) {
                updateCheckState = .available(latestInfo)
                softwareUpdateWindowController.show(updateInfo: latestInfo, preferences: preferences)
            } else {
                updateCheckState = .upToDate(version: latestInfo.version)
            }
        } catch {
            lastUpdateCheckDate = .now
            updateCheckState = .failed(String(localized: "检查更新失败，请稍后重试"))
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

    private var filteredConverterCurrencies: [CurrencyInfo] {
        let query = converterCurrencySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return CurrencyCatalog.all
        }

        return CurrencyCatalog.all.filter { currency in
            CurrencyCatalog.matchesSearch(currency, query: query)
        }
    }

    private var currentDraftAlreadySelected: Bool {
        guard let currentDraftPair else {
            return false
        }

        return preferences.contains(currentDraftPair)
    }

    private var resolvedDraftConverterCurrencyCode: String {
        if filteredConverterCurrencies.contains(where: { $0.code == draftConverterCurrencyCode }) {
            return draftConverterCurrencyCode
        }

        return filteredConverterCurrencies.first?.code ?? "USD"
    }

    private var converterCurrencyAlreadySelected: Bool {
        preferences.converterCurrencyCodes.contains(resolvedDraftConverterCurrencyCode)
    }

    private var resolvedAlertPairID: String {
        if preferences.selectedPairIDs.contains(alertPairID) {
            return alertPairID
        }

        return preferences.selectedPairIDs.first ?? ""
    }

    private var canShowDraftPickers: Bool {
        !filteredBaseCurrencies.isEmpty && !filteredQuoteCurrencies.isEmpty
    }

    private var searchKeyword: String {
        currencySearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Capsule(style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3, height: 15)

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10))
            )
    }

    private func displayPreferencePicker(
        title: LocalizedStringKey,
        selection: Binding<Int>,
        options: [Int],
        label: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func converterCurrencyRow(for code: String) -> some View {
        HStack(spacing: 12) {
            Text(CurrencyCatalog.flag(for: code))
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(code)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(CurrencyCatalog.name(for: code))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            converterCurrencyOrderControls(for: code)

            Button("移除") {
                preferences.removeConverterCurrency(code: code)
                Task {
                    await viewModel.selectedPairsDidChange()
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func converterCurrencyOrderControls(for code: String) -> some View {
        HStack(spacing: 2) {
            Button {
                preferences.moveConverterCurrencyUp(code: code)
                viewModel.presentationDidChange()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(preferences.converterCurrencyCodes.first == code)
            .help("上移")

            Button {
                preferences.moveConverterCurrencyDown(code: code)
                viewModel.presentationDidChange()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(preferences.converterCurrencyCodes.last == code)
            .help("下移")
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func currencyCodeWrap(_ codes: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(codes, id: \.self) { code in
                HStack(spacing: 6) {
                    Text(CurrencyCatalog.flag(for: code))
                    Text(code)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(sectionSurfaceColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(sectionStrokeColor, lineWidth: 1)
            )
            .shadow(color: sectionShadowColor, radius: 10, x: 0, y: 4)
    }

    private var pageHeaderBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(headerSurfaceColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(sectionStrokeColor, lineWidth: 1)
            )
            .shadow(color: sectionShadowColor.opacity(0.7), radius: 8, x: 0, y: 3)
    }

    private func sidebarRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.18) : Color.clear, lineWidth: 1)
            )
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08))
            .frame(width: 1)
    }

    private var sidebarBackground: some View {
        Color(nsColor: .underPageBackgroundColor)
            .opacity(colorScheme == .dark ? 0.74 : 0.58)
    }

    private var detailPaneBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.025),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
            }
    }

    private var windowBackground: some View {
        Color(nsColor: .windowBackgroundColor)
    }

    private var sectionSurfaceColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.72 : 0.92)
    }

    private var headerSurfaceColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.62 : 0.86)
    }

    private var sectionStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.06)
    }

    private var sectionShadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06)
    }

    private var currentAppLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
        let locale = Locale(identifier: code)
        let nativeName = locale.localizedString(forIdentifier: code)
        let userVisibleName = Locale.autoupdatingCurrent.localizedString(forIdentifier: code)

        if let nativeName, let userVisibleName, nativeName != userVisibleName {
            return "\(nativeName) · \(userVisibleName)"
        }

        return nativeName ?? userVisibleName ?? code
    }

    private func openLanguageSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.language"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                languageSettingsMessage = String(localized: "语言设置已打开")
                return
            }
        }

        languageSettingsMessage = String(localized: "无法打开语言设置")
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportDiagnostics() {
        let report = diagnosticsReportText()
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = baseURL.appendingPathComponent("CurrencyTracker", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let timestamp = Self.diagnosticFileFormatter.string(from: .now)
            let fileURL = directoryURL.appendingPathComponent("diagnostics-\(timestamp).txt")
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            diagnosticExportMessage = String(format: String(localized: "已导出到 %@"), fileURL.lastPathComponent)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } catch {
            diagnosticExportMessage = String(format: String(localized: "导出失败：%@"), error.localizedDescription)
        }
    }

    private func diagnosticsReportText() -> String {
        let bundle = Bundle.main
        let version = SoftwareUpdateChecker.currentVersion(bundle: bundle)
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let selectedPairs = preferences.selectedPairs.map(\.compactLabel).joined(separator: ", ")
        let converterCurrencies = preferences.effectiveConverterCurrencyCodes.joined(separator: ", ")
        let sourceStatuses = viewModel.sourceStatuses.map {
            "- \($0.source.displayName): \($0.state.rawValue) · \($0.message) · \(ExchangeFormatter.time.string(from: $0.timestamp))"
        }.joined(separator: "\n")
        let logs = viewModel.refreshLog.prefix(20).map {
            "- \(ExchangeFormatter.time.string(from: $0.timestamp)) [\($0.level.rawValue)] \($0.message)"
        }.joined(separator: "\n")

        return """
        Currency Tracker Diagnostics
        Generated: \(Date())

        App
        - Version: \(version)
        - Build: \(build)
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)

        Preferences
        - Base currency: \(preferences.baseCurrencyCode)
        - Selected pairs: \(selectedPairs.isEmpty ? "none" : selectedPairs)
        - Converter linked to pairs: \(preferences.converterCurrenciesFollowSelectedPairs)
        - Converter currencies: \(converterCurrencies.isEmpty ? "none" : converterCurrencies)
        - Auto refresh: \(refreshIntervalTitle(for: preferences.autoRefreshMinutes))
        - Refresh on menu open: \(preferences.menuBarOpenRefreshEnabled)
        - Menu bar display: \(preferences.menuBarDisplayMode.rawValue)
        - Rate display base amount: \(preferences.rateDisplayBaseAmount)
        - Conversion fraction digits: \(preferences.conversionFractionDigits)
        - Profiles: \(preferences.settingsProfiles.count)
        - Rate alerts: \(preferences.rateAlerts.count)
        - Custom API providers: \(preferences.customAPIProviders.count)

        Permissions
        - Accessibility trusted: \(AXIsProcessTrusted())
        - Launch at login: \(launchController.isEnabled)
        - Launch approval required: \(launchController.requiresApproval)

        Source Statuses
        \(sourceStatuses.isEmpty ? "none" : sourceStatuses)

        Recent Logs
        \(logs.isEmpty ? "none" : logs)
        """
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

    private func syncConverterCurrencySelectionToSearchResults() {
        if let firstCurrency = filteredConverterCurrencies.first,
           filteredConverterCurrencies.contains(where: { $0.code == draftConverterCurrencyCode }) == false {
            draftConverterCurrencyCode = firstCurrency.code
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

    private func profileSummaryText(for profile: SettingsProfile) -> String {
        let converterText = profile.converterCurrenciesFollowSelectedPairs
            ? String(localized: "换算联动")
            : String(format: String(localized: "%d 个换算币种"), profile.converterCurrencyCodes.count)
        return String(
            format: String(localized: "%d 个汇率 · %@ · 基准 %@ · %@ · %d 基数 · %d 位"),
            profile.selectedPairIDs.count,
            converterText,
            profile.baseCurrencyCode,
            refreshIntervalTitle(for: profile.autoRefreshMinutes),
            profile.rateDisplayBaseAmount,
            profile.conversionFractionDigits
        )
    }

    private func pairSubtitle(for pair: CurrencyPair) -> String {
        "\(preferences.rateDisplayBaseAmount) \(pair.baseCode) → \(pair.quoteCode)"
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

    private static let diagnosticFileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
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

                HStack(spacing: 5) {
                    Image(systemName: statusSymbolName)
                        .font(.system(size: 9, weight: .bold))
                    Text(LocalizedStringKey(field.phase.statusText))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
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

    private var statusSymbolName: String {
        switch field.phase {
        case .enabled:
            "checkmark.circle.fill"
        case .failure:
            "exclamationmark.triangle.fill"
        case .saving:
            "circle.dotted"
        case .editing:
            "pencil.circle"
        case .empty:
            "circle"
        }
    }
}

private struct RateAlertRow: View {
    let alert: RateAlert
    let pair: CurrencyPair?
    let onChange: (RateAlert) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { alert.isEnabled },
                set: {
                    var updatedAlert = alert
                    updatedAlert.isEnabled = $0
                    onChange(updatedAlert)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(pair?.compactLabel ?? alert.pairID)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("\(alert.direction.title) \(ExchangeFormatter.decimal.string(from: alert.threshold as NSNumber) ?? "\(alert.threshold)")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastTriggeredAt = alert.lastTriggeredAt {
                Text(String(format: String(localized: "上次触发 %@"), ExchangeFormatter.time.string(from: lastTriggeredAt)))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Button("删除") {
                onDelete()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }
}

private enum CustomAPIProviderRowPhase: Equatable {
    case incomplete
    case disabled
    case enabled
    case editing
    case testing
    case failure(String)

    var statusText: String {
        switch self {
        case .incomplete:
            String(localized: "请填写 URL 模板和 JSON path")
        case .disabled:
            String(localized: "已停用")
        case .enabled:
            String(localized: "已启用")
        case .editing:
            String(localized: "编辑中")
        case .testing:
            String(localized: "测试中")
        case .failure(let message):
            message
        }
    }

    var tintColor: Color {
        switch self {
        case .enabled:
            Color(red: 0.09, green: 0.53, blue: 0.32)
        case .testing:
            Color(red: 0.08, green: 0.43, blue: 0.74)
        case .failure:
            Color(red: 0.74, green: 0.20, blue: 0.18)
        case .incomplete:
            Color(red: 0.78, green: 0.50, blue: 0.11)
        case .disabled, .editing:
            .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .enabled:
            "checkmark.circle.fill"
        case .testing:
            "circle.dotted"
        case .failure, .incomplete:
            "exclamationmark.triangle.fill"
        case .editing:
            "pencil.circle"
        case .disabled:
            "pause.circle"
        }
    }
}

private struct CustomAPIProviderRow: View {
    let provider: CustomAPIProvider
    @State private var draftProvider: CustomAPIProvider
    @State private var isEditing: Bool
    @State private var isRevealed = false
    @State private var isTesting = false
    @State private var phase: CustomAPIProviderRowPhase
    let onChange: (CustomAPIProvider) -> Void
    let onDelete: () -> Void

    init(provider: CustomAPIProvider, onChange: @escaping (CustomAPIProvider) -> Void, onDelete: @escaping () -> Void) {
        self.provider = provider
        _draftProvider = State(initialValue: provider)
        let startsEditing = provider.isUsable == false
        _isEditing = State(initialValue: startsEditing)
        _phase = State(initialValue: startsEditing ? .editing : Self.statusPhase(for: provider))
        self.onChange = onChange
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { draftProvider.isEnabled },
                    set: { newValue in
                        draftProvider.isEnabled = newValue
                        if isEditing {
                            phase = .editing
                        } else {
                            persistDraft()
                        }
                    }
                ))
                    .toggleStyle(.switch)
                    .labelsHidden()

                TextField("名称", text: binding(\.name))
                    .textFieldStyle(.roundedBorder)
                    .disabled(isEditing == false)

                HStack(spacing: 5) {
                    Image(systemName: phase.symbolName)
                        .font(.system(size: 10, weight: .bold))
                    Text(phase.statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(phase.tintColor)
                .frame(minWidth: 82, alignment: .leading)

                Button("删除") {
                    onDelete()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            TextField("URL 模板，例如 https://api.example.com/rate?base={base}&quote={quote}&key={key}", text: binding(\.urlTemplate))
                .textFieldStyle(.roundedBorder)
                .disabled(isEditing == false)

            HStack(spacing: 10) {
                Group {
                    if isRevealed {
                        TextField("API Key（可选）", text: binding(\.apiKey))
                    } else {
                        SecureField("API Key（可选）", text: binding(\.apiKey))
                    }
                }
                .textFieldStyle(.roundedBorder)
                .disabled(isEditing == false)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(draftProvider.apiKey.isEmpty ? .tertiary : .secondary)
                .disabled(draftProvider.apiKey.isEmpty)

                TextField("JSON path，例如 rate 或 data.rate", text: binding(\.ratePath))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .disabled(isEditing == false)
            }

            HStack(spacing: 10) {
                Button("测试连接") {
                    Task {
                        await testConnection()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting || draftProvider.isUsable == false)

                Spacer()

                Group {
                    if isEditing {
                        Button("保存") {
                            persistDraft()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("编辑") {
                            isEditing = true
                            phase = .editing
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .onChange(of: provider) { _, newProvider in
            refreshFromProviderIfNeeded(newProvider)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CustomAPIProvider, Value>) -> Binding<Value> {
        Binding(
            get: { draftProvider[keyPath: keyPath] },
            set: { newValue in
                draftProvider[keyPath: keyPath] = newValue
                if isEditing {
                    phase = .editing
                }
            }
        )
    }

    private func persistDraft(phaseOverride: CustomAPIProviderRowPhase? = nil) {
        var normalizedProvider = draftProvider
        normalizedProvider.name = normalizedProvider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedProvider.urlTemplate = normalizedProvider.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedProvider.apiKey = normalizedProvider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedProvider.ratePath = normalizedProvider.ratePath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedProvider.isUsable || normalizedProvider.isEnabled == false else {
            isEditing = true
            phase = .failure(String(localized: "请填写 URL 模板和 JSON path"))
            return
        }

        draftProvider = normalizedProvider
        isEditing = false
        isRevealed = false
        onChange(normalizedProvider)
        phase = phaseOverride ?? Self.statusPhase(for: normalizedProvider)
    }

    @MainActor
    private func testConnection() async {
        var providerToTest = draftProvider
        providerToTest.name = providerToTest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        providerToTest.urlTemplate = providerToTest.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        providerToTest.apiKey = providerToTest.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        providerToTest.ratePath = providerToTest.ratePath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard providerToTest.isUsable else {
            phase = .failure(String(localized: "请填写 URL 模板和 JSON path"))
            isEditing = true
            return
        }

        isTesting = true
        phase = .testing
        let result = await CustomAPIProviderValidator.validate(provider: providerToTest)
        isTesting = false

        switch result {
        case .success:
            providerToTest.isEnabled = true
            draftProvider = providerToTest
            persistDraft(phaseOverride: .enabled)
        case .failure(let error):
            isEditing = true
            phase = .failure(error.message)
        }
    }

    private func refreshFromProviderIfNeeded(_ provider: CustomAPIProvider) {
        guard isEditing == false else {
            return
        }

        draftProvider = provider
        phase = Self.statusPhase(for: provider)
    }

    private static func statusPhase(for provider: CustomAPIProvider) -> CustomAPIProviderRowPhase {
        guard provider.isUsable else {
            return .incomplete
        }

        return provider.isEnabled ? .enabled : .disabled
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
