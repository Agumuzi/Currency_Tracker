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
    private let userDefaults: UserDefaults
    private let preferences: PreferencesStore
    private let credentialStore: EnhancedSourceCredentialStore
    private let launchController: LaunchAtLoginController
    private let settingsWindowController: SettingsWindowController
    private let panelWindowController: PanelWindowController
    private let serviceActionHandler: ServiceActionHandler
    private let globalShortcutHandler: GlobalShortcutHandler
    private let initialLaunchCoordinator: InitialLaunchCoordinator
    private let isRunningUITests: Bool
    @State private var viewModel: ExchangePanelViewModel

    init() {
        let isRunningUITests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let userDefaults = Self.makeUserDefaults()
        let preferences = PreferencesStore(userDefaults: userDefaults)
        let credentialStore = Self.makeCredentialStore(userDefaults: userDefaults)
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
            globalShortcutHandler: globalShortcutHandler
        )
        panelWindowController.configurePinnedWindowFactory {
            let rootView = ContentView(
                viewModel: viewModel,
                preferences: preferences,
                settingsWindowController: settingsWindowController,
                panelWindowController: panelWindowController,
                autoBootstrap: false,
                presentationMode: .pinned
            )
            let hostingController = NSHostingController(rootView: rootView)
            return DetachedPinnedPanelWindow(
                contentViewController: hostingController,
                contentSize: NSSize(width: 424, height: 520)
            )
        }
        let initialLaunchCoordinator = InitialLaunchCoordinator(
            userDefaults: userDefaults,
            settingsWindowController: settingsWindowController,
            isRunningUITests: isRunningUITests
        )
        self.isRunningUITests = isRunningUITests
        self.userDefaults = userDefaults
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.settingsWindowController = settingsWindowController
        self.panelWindowController = panelWindowController
        self.serviceActionHandler = serviceActionHandler
        self.globalShortcutHandler = globalShortcutHandler
        self.initialLaunchCoordinator = initialLaunchCoordinator
        _viewModel = State(initialValue: viewModel)
        NSApplication.shared.setActivationPolicy(isRunningUITests ? .regular : .accessory)
        serviceActionHandler.register()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(
                viewModel: viewModel,
                preferences: preferences,
                settingsWindowController: settingsWindowController,
                panelWindowController: panelWindowController,
                autoBootstrap: !isRunningUITests,
                presentationMode: .menuBar
            )
        } label: {
            Image(systemName: "banknote.fill")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .help(viewModel.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
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

    private static func makeCredentialStore(userDefaults: UserDefaults) -> EnhancedSourceCredentialStore {
        let environment = ProcessInfo.processInfo.environment

        if environment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] == "1" {
            return EnhancedSourceCredentialStore(
                secretStore: EphemeralSecretStore(),
                userDefaults: userDefaults
            )
        }

        return EnhancedSourceCredentialStore(userDefaults: userDefaults)
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
        globalShortcutHandler: GlobalShortcutHandler
    ) {
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.viewModel = viewModel
        self.service = service
        self.dockVisibilityController = dockVisibilityController
        self.globalShortcutHandler = globalShortcutHandler
        super.init()
    }

    func show(section: SettingsSection? = nil) {
        focusSection = section
        if windowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeRootView()))
            window.identifier = NSUserInterfaceItemIdentifier("currency-tracker-settings-window")
            window.delegate = self
            window.title = "Currency Tracker"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unifiedCompact
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 880, height: 600))
            window.minSize = NSSize(width: 780, height: 540)
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

        dockVisibilityController.restoreMenuBarOnlyMode()
    }

    private func makeRootView() -> SettingsView {
        SettingsView(
            preferences: preferences,
            launchController: launchController,
            viewModel: viewModel,
            apiConfigurationViewModel: apiConfigurationViewModel,
            globalShortcutHandler: globalShortcutHandler,
            focusSection: focusSection
        )
    }
}
