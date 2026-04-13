//
//  DockVisibilityController.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import AppKit

protocol ApplicationActivationControlling: Sendable {
    @MainActor func activationPolicy() -> NSApplication.ActivationPolicy
    @MainActor func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy)
}

struct SharedApplicationActivationController: ApplicationActivationControlling {
    @MainActor
    func activationPolicy() -> NSApplication.ActivationPolicy {
        NSApplication.shared.activationPolicy()
    }

    @MainActor
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) {
        NSApplication.shared.setActivationPolicy(activationPolicy)
    }
}

@MainActor
final class DockVisibilityController {
    private let applicationController: any ApplicationActivationControlling
    private let logHandler: @MainActor (RefreshLogEntry.Level, String) -> Void

    init(
        applicationController: (any ApplicationActivationControlling)? = nil,
        logHandler: @escaping @MainActor (RefreshLogEntry.Level, String) -> Void
    ) {
        self.applicationController = applicationController ?? SharedApplicationActivationController()
        self.logHandler = logHandler
    }

    func showDockForSettingsWindow() {
        let didChange = applicationController.activationPolicy() != .regular
        applicationController.setActivationPolicy(.regular)

        if didChange {
            logHandler(.info, "设置窗口已打开，Dock 图标已显示")
        } else {
            logHandler(.info, "设置窗口已打开，Dock 图标保持显示")
        }
    }

    func restoreMenuBarOnlyMode() {
        let didChange = applicationController.activationPolicy() != .accessory
        applicationController.setActivationPolicy(.accessory)

        if didChange {
            logHandler(.info, "设置窗口已关闭，Dock 图标已隐藏")
        } else {
            logHandler(.info, "设置窗口已关闭，Dock 图标保持隐藏")
        }
    }
}
