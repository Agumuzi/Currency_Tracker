//
//  ServiceActionHandler.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import AppKit
import Foundation

@MainActor
final class ServiceActionHandler: NSObject {
    private let coordinator: ConversionCoordinator

    init(coordinator: ConversionCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func register() {
        let portName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Currency Tracker"
        NSApplication.shared.servicesProvider = self
        NSRegisterServicesProvider(self, portName)
        NSUpdateDynamicServices()
    }

    @objc(convertSelectionToBaseCurrency:userData:error:)
    func convertSelectionToBaseCurrency(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = pasteboard.string(forType: .string),
              selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            error.pointee = "无法读取选中文本" as NSString
            Task { @MainActor in
                await coordinator.handleSelectedText("", source: .services)
            }
            return
        }

        Task { @MainActor in
            await coordinator.handleSelectedText(selectedText, source: .services)
        }
    }
}

@MainActor
final class InitialLaunchCoordinator {
    private let userDefaults: UserDefaults
    private let preferences: PreferencesStore
    private let settingsWindowController: SettingsWindowController
    private let automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator
    private let isRunningUITests: Bool
    private var observer: NSObjectProtocol?
    private var didHandleInitialPresentation = false

    init(
        userDefaults: UserDefaults,
        preferences: PreferencesStore,
        settingsWindowController: SettingsWindowController,
        automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator,
        isRunningUITests: Bool
    ) {
        self.userDefaults = userDefaults
        self.preferences = preferences
        self.settingsWindowController = settingsWindowController
        self.automaticUpdateCoordinator = automaticUpdateCoordinator
        self.isRunningUITests = isRunningUITests
        self.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                await self?.handleApplicationDidFinishLaunching(notification)
            }
        }

        if Self.shouldShowSettingsForUITest {
            Task { @MainActor [self] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                await presentInitialSettingsIfNeeded(isDefaultLaunch: true, forceShowSettings: true)
            }
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    private func handleApplicationDidFinishLaunching(_ notification: Notification) async {
        let shouldShowSettingsForUITest = Self.shouldShowSettingsForUITest
        if isRunningUITests && !shouldShowSettingsForUITest {
            return
        }

        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? true
        guard isDefaultLaunch || shouldShowSettingsForUITest else {
            return
        }

        await presentInitialSettingsIfNeeded(isDefaultLaunch: isDefaultLaunch, forceShowSettings: shouldShowSettingsForUITest)
    }

    private func presentInitialSettingsIfNeeded(isDefaultLaunch: Bool, forceShowSettings: Bool) async {
        guard didHandleInitialPresentation == false else {
            return
        }

        if isRunningUITests && !forceShowSettings {
            didHandleInitialPresentation = true
            return
        }

        guard isDefaultLaunch || forceShowSettings else {
            return
        }

        if await SoftwareUpdatePermissionRecovery.shouldPresentReviewAfterLaunch(userDefaults: userDefaults) {
            didHandleInitialPresentation = true
            settingsWindowController.show(section: .permissions)
            return
        }

        let hasShownInitialSettingsWindow = userDefaults.bool(forKey: "hasShownInitialSettingsWindow")
        let isDebugLaunch = ProcessInfo.processInfo.arguments.contains("-NSDocumentRevisionsDebugMode")
        let shouldPresent = forceShowSettings || !hasShownInitialSettingsWindow || isDebugLaunch || !preferences.menuBarItemEnabled
        guard shouldPresent else {
            didHandleInitialPresentation = true
            automaticUpdateCoordinator.checkIfNeeded()
            return
        }

        didHandleInitialPresentation = true
        userDefaults.set(true, forKey: "hasShownInitialSettingsWindow")
        settingsWindowController.show()
    }

    private static var shouldShowSettingsForUITest: Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments

        return environment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] == "1"
            || arguments.contains("-CurrencyTrackerUITestShowSettings")
    }
}
