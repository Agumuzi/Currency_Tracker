//
//  Currency_TrackerApp.swift
//  Currency Tracker
//
//  Created by Thomas Tao on 4/10/26.
//

import AppKit
import SwiftUI

@main
struct Currency_TrackerApp: App {
    @NSApplicationDelegateAdaptor(ApplicationLifecycleController.self) private var lifecycleController

    private let userDefaults: UserDefaults
    private let preferences: PreferencesStore
    private let credentialStore: EnhancedSourceCredentialStore
    private let launchController: LaunchAtLoginController
    private let settingsWindowController: SettingsWindowController
    private let panelWindowController: PanelWindowController
    private let softwareUpdateWindowController: SoftwareUpdateWindowController
    private let automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator
    private let serviceActionHandler: ServiceActionHandler
    private let globalShortcutHandler: GlobalShortcutHandler
    private let initialLaunchCoordinator: InitialLaunchCoordinator
    private let isRunningUITests: Bool
    @State private var viewModel: ExchangePanelViewModel

    init() {
        let isRunningUITests = Self.isRunningUITests()
        let userDefaults = Self.makeUserDefaults()
        let secretStore = Self.makeSecretStore()
        let preferences = PreferencesStore(userDefaults: userDefaults, secretStore: secretStore)
        let credentialStore = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: userDefaults)
        let launchController = LaunchAtLoginController()
        let service = ExchangeRateService()
        let store = ExchangeRateStore()
        let viewModel = ExchangePanelViewModel(
            preferences: preferences,
            credentialStore: credentialStore,
            service: service,
            store: store,
            previewState: isRunningUITests ? .sample : nil
        )
        let dockVisibilityController = DockVisibilityController { level, message in
            viewModel.recordInternalEvent(message, level: level)
        }
        let panelWindowController = PanelWindowController(viewModel: viewModel)
        let softwareUpdateWindowController = SoftwareUpdateWindowController()
        let promptPanel = LightweightPromptPanel()
        let clipboardWriter = ClipboardWriter()
        let conversionCoordinator = ConversionCoordinator(
            preferences: preferences,
            credentialStore: credentialStore,
            service: service,
            store: store,
            promptPanel: promptPanel,
            clipboardWriter: clipboardWriter,
            liveLogHandler: { level, message in
                viewModel.recordInternalEvent(message, level: level)
            },
            snapshotMergeHandler: { snapshots in
                viewModel.mergeServiceSnapshots(snapshots)
            }
        )
        let globalShortcutHandler = GlobalShortcutHandler(
            preferences: preferences,
            coordinator: conversionCoordinator,
            popupPresenter: promptPanel,
            logHandler: { level, message in
                viewModel.recordInternalEvent(message, level: level)
            }
        )
        let serviceActionHandler = ServiceActionHandler(coordinator: conversionCoordinator)
        let settingsWindowController = SettingsWindowController(
            preferences: preferences,
            credentialStore: credentialStore,
            launchController: launchController,
            viewModel: viewModel,
            service: service,
            dockVisibilityController: dockVisibilityController,
            globalShortcutHandler: globalShortcutHandler,
            softwareUpdateWindowController: softwareUpdateWindowController
        )
        panelWindowController.configurePinnedContent { controller in
            AnyView(
                ContentView(
                    viewModel: viewModel,
                    preferences: preferences,
                    settingsWindowController: settingsWindowController,
                    panelWindowController: controller,
                    autoBootstrap: false,
                    presentationMode: .pinned
                )
            )
        }
        let automaticUpdateCoordinator = AutomaticSoftwareUpdateCoordinator(
            preferences: preferences,
            updateWindowController: softwareUpdateWindowController,
            isRunningUITests: isRunningUITests
        )
        let initialLaunchCoordinator = InitialLaunchCoordinator(
            userDefaults: userDefaults,
            preferences: preferences,
            settingsWindowController: settingsWindowController,
            automaticUpdateCoordinator: automaticUpdateCoordinator,
            isRunningUITests: isRunningUITests
        )
        self.isRunningUITests = isRunningUITests
        self.userDefaults = userDefaults
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.settingsWindowController = settingsWindowController
        self.panelWindowController = panelWindowController
        self.softwareUpdateWindowController = softwareUpdateWindowController
        self.automaticUpdateCoordinator = automaticUpdateCoordinator
        self.serviceActionHandler = serviceActionHandler
        self.globalShortcutHandler = globalShortcutHandler
        self.initialLaunchCoordinator = initialLaunchCoordinator
        _viewModel = State(initialValue: viewModel)
        NSApplication.shared.setActivationPolicy(isRunningUITests || !preferences.menuBarItemEnabled ? .regular : .accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Currency Tracker menu bar app remains active")
        lifecycleController.configure { [weak settingsWindowController] in
            settingsWindowController?.show()
        }
        serviceActionHandler.register()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { preferences.menuBarItemEnabled },
            set: { preferences.setMenuBarItemEnabled($0) }
        )) {
            ContentView(
                viewModel: viewModel,
                preferences: preferences,
                settingsWindowController: settingsWindowController,
                panelWindowController: panelWindowController,
                autoBootstrap: !isRunningUITests,
                presentationMode: .menuBar
            )
        } label: {
            menuBarLabel
                .help(viewModel.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let featuredCard = viewModel.cards.first { $0.id == viewModel.featuredPairID } ?? viewModel.cards.first
        switch preferences.menuBarDisplayMode {
        case .iconOnly:
            Image(systemName: "banknote.fill")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        case .featuredRate:
            if let featuredCard, featuredCard.snapshot != nil {
                Text(featuredCard.valueText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } else {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        case .compactPair:
            if let featuredCard, featuredCard.snapshot != nil {
                HStack(spacing: 4) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(featuredCard.compactPairLabel) \(featuredCard.valueText)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            } else {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private static func makeUserDefaults() -> UserDefaults {
        let environment = ProcessInfo.processInfo.environment
        guard let suiteName = environment["CURRENCY_TRACKER_DEFAULTS_SUITE"],
              let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }

        if environment["CURRENCY_TRACKER_RESET_DEFAULTS"] == "1" {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return defaults
    }

    private static func isRunningUITests() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments

        return environment["XCTestConfigurationFilePath"] != nil
            || environment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] == "1"
            || arguments.contains("-CurrencyTrackerUITestShowSettings")
    }

    private static func makeSecretStore() -> any SecretStoring {
        let environment = ProcessInfo.processInfo.environment

        if environment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] == "1" {
            return EphemeralSecretStore()
        }

        return LocalSecretStore(service: "com.thomas.currency-tracker")
    }
}

@MainActor
final class ApplicationLifecycleController: NSObject, NSApplicationDelegate {
    private static weak var current: ApplicationLifecycleController?
    private var reopenHandler: (() -> Void)?
    private var allowsTermination = false

    override init() {
        super.init()
        Self.current = self
    }

    func configure(reopenHandler: @escaping () -> Void) {
        self.reopenHandler = reopenHandler
    }

    static func terminate(_ sender: Any? = nil) {
        current?.allowsTermination = true
        NSApplication.shared.terminate(sender)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowsTermination ? .terminateNow : .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenHandler?()
        return false
    }

}

private final class EphemeralSecretStore: SecretStoring {
    private var values: [String: String] = [:]

    func read(account: String) throws -> String? {
        values[account]
    }

    func write(_ value: String, account: String) throws {
        values[account] = value
    }

    func delete(account: String) throws {
        values[account] = nil
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: PreferencesStore
    private let credentialStore: EnhancedSourceCredentialStore
    private let launchController: LaunchAtLoginController
    private let viewModel: ExchangePanelViewModel
    private let service: ExchangeRateService
    private let dockVisibilityController: DockVisibilityController
    private let globalShortcutHandler: GlobalShortcutHandler
    private let softwareUpdateWindowController: SoftwareUpdateWindowController
    private lazy var apiConfigurationViewModel = APIConfigurationViewModel(
        credentialStore: credentialStore,
        service: service,
        logHandler: { [weak self] level, message in
            self?.viewModel.recordInternalEvent(message, level: level)
        }
    )
    private var windowController: NSWindowController?
    private var focusSection: SettingsSection?

    init(
        preferences: PreferencesStore,
        credentialStore: EnhancedSourceCredentialStore,
        launchController: LaunchAtLoginController,
        viewModel: ExchangePanelViewModel,
        service: ExchangeRateService,
        dockVisibilityController: DockVisibilityController,
        globalShortcutHandler: GlobalShortcutHandler,
        softwareUpdateWindowController: SoftwareUpdateWindowController
    ) {
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.viewModel = viewModel
        self.service = service
        self.dockVisibilityController = dockVisibilityController
        self.globalShortcutHandler = globalShortcutHandler
        self.softwareUpdateWindowController = softwareUpdateWindowController
        super.init()
    }

    func show(section: SettingsSection? = nil) {
        focusSection = section
        if windowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeRootView()))
            window.identifier = NSUserInterfaceItemIdentifier("currency-tracker-settings-window")
            window.delegate = self
            window.title = "Currency Tracker"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unifiedCompact
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 880, height: 600))
            window.minSize = NSSize(width: 780, height: 540)
            window.setFrameAutosaveName("currency-tracker-settings-window")
            window.center()

            windowController = NSWindowController(window: window)
        } else if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: makeRootView())
        }

        dockVisibilityController.showDockForSettingsWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == windowController?.window else {
            return
        }

        dockVisibilityController.restoreMenuBarOnlyMode(shouldHideDock: preferences.menuBarItemEnabled)
        if preferences.menuBarItemEnabled == false && preferences.backgroundActivityEnabled == false {
            ApplicationLifecycleController.terminate(nil)
        }
    }

    private func makeRootView() -> SettingsView {
        SettingsView(
            preferences: preferences,
            launchController: launchController,
            viewModel: viewModel,
            apiConfigurationViewModel: apiConfigurationViewModel,
            globalShortcutHandler: globalShortcutHandler,
            softwareUpdateWindowController: softwareUpdateWindowController,
            focusSection: focusSection
        )
    }
}
