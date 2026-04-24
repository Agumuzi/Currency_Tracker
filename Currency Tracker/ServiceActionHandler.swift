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
    private let settingsWindowController: SettingsWindowController
    private let automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator
    private let isRunningUITests: Bool
    private var observer: NSObjectProtocol?

    init(
        userDefaults: UserDefaults,
        settingsWindowController: SettingsWindowController,
        automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator,
        isRunningUITests: Bool
    ) {
        self.userDefaults = userDefaults
        self.settingsWindowController = settingsWindowController
        self.automaticUpdateCoordinator = automaticUpdateCoordinator
        self.isRunningUITests = isRunningUITests
        self.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { [weak self] in
                self?.handleApplicationDidFinishLaunching(notification)
            }
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    private func handleApplicationDidFinishLaunching(_ notification: Notification) {
        let shouldShowSettingsForUITest = ProcessInfo.processInfo.environment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] == "1"
        if isRunningUITests && !shouldShowSettingsForUITest {
            return
        }

        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? true
        guard isDefaultLaunch || shouldShowSettingsForUITest else {
            return
        }

        let hasShownInitialSettingsWindow = userDefaults.bool(forKey: "hasShownInitialSettingsWindow")
        let isDebugLaunch = ProcessInfo.processInfo.arguments.contains("-NSDocumentRevisionsDebugMode")
        let shouldPresent = !hasShownInitialSettingsWindow || isDebugLaunch
        guard shouldPresent else {
            automaticUpdateCoordinator.checkIfNeeded()
            return
        }

        userDefaults.set(true, forKey: "hasShownInitialSettingsWindow")
        settingsWindowController.show()
    }
}
