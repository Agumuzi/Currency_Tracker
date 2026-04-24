//
//  PanelWindowController.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import AppKit
import Observation
import SwiftUI

enum PanelPresentationMode: Sendable, Equatable {
    case menuBar
    case pinned
}

@MainActor
@Observable
final class PanelWindowController: NSObject, NSWindowDelegate {
    private weak var menuBarWindow: NSWindow?
    private weak var pinnedWindow: NSWindow?
    private var originalLevel: NSWindow.Level?
    private var originalCollectionBehavior: NSWindow.CollectionBehavior?
    private var originalMovableByBackground: Bool?
    private var originalHidesOnDeactivate: Bool?
    var isPinned = false

    private let viewModel: ExchangePanelViewModel

    init(viewModel: ExchangePanelViewModel) {
        self.viewModel = viewModel
    }

    func registerMenuBarWindow(_ window: NSWindow?) {
        guard let window else {
            return
        }

        if isPinned {
            if let pinnedWindow, window !== pinnedWindow {
                window.orderOut(nil)
                pinnedWindow.makeKeyAndOrderFront(nil)
                return
            }

            if pinnedWindow == nil {
                pinnedWindow = window
                captureOriginalConfigurationIfNeeded(from: window)
                applyPinnedConfiguration(to: window)
            }
        }

        menuBarWindow = window
    }

    func dismissTransientMenuWindowIfNeeded(_ window: NSWindow?) {
        guard isPinned,
              let window,
              window !== pinnedWindow else {
            return
        }

        window.orderOut(nil)
        pinnedWindow?.makeKeyAndOrderFront(nil)
    }

    func togglePinnedPanel(from sourceWindow: NSWindow?) {
        if isPinned {
            unpin()
        } else {
            pin(window: sourceWindow ?? menuBarWindow)
        }
    }

    private func pin(window: NSWindow?) {
        guard let window else {
            return
        }

        menuBarWindow = window
        pinnedWindow = window
        captureOriginalConfigurationIfNeeded(from: window)
        applyPinnedConfiguration(to: window)
        window.makeKeyAndOrderFront(nil)
        applyPinnedState(logMessage: "汇率面板已锁定，自动刷新已暂停")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func unpin() {
        guard let window = pinnedWindow ?? menuBarWindow else {
            applyUnpinnedState(logMessage: "汇率面板已解除锁定，自动刷新已恢复")
            return
        }

        if let originalLevel {
            window.level = originalLevel
        }

        if let originalCollectionBehavior {
            window.collectionBehavior = originalCollectionBehavior
        }

        if let originalMovableByBackground {
            window.isMovableByWindowBackground = originalMovableByBackground
        }

        if let panel = window as? NSPanel, let originalHidesOnDeactivate {
            panel.hidesOnDeactivate = originalHidesOnDeactivate
        }

        pinnedWindow = nil
        resetOriginalConfiguration()
        applyUnpinnedState(logMessage: "汇率面板已解除锁定，自动刷新已恢复")
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === pinnedWindow else {
            return
        }

        pinnedWindow = nil
        resetOriginalConfiguration()
        applyUnpinnedState(logMessage: "汇率面板已关闭，自动刷新已恢复")
    }

    private func captureOriginalConfigurationIfNeeded(from window: NSWindow) {
        if originalLevel == nil {
            originalLevel = window.level
        }

        if originalCollectionBehavior == nil {
            originalCollectionBehavior = window.collectionBehavior
        }

        if originalMovableByBackground == nil {
            originalMovableByBackground = window.isMovableByWindowBackground
        }

        if originalHidesOnDeactivate == nil, let panel = window as? NSPanel {
            originalHidesOnDeactivate = panel.hidesOnDeactivate
        }
    }

    private func applyPinnedConfiguration(to window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        if let panel = window as? NSPanel {
            panel.hidesOnDeactivate = false
        }
    }

    private func applyPinnedState(logMessage: String) {
        guard isPinned == false else {
            return
        }

        isPinned = true
        viewModel.setPanelPinned(true)
        viewModel.recordInternalEvent(logMessage)
    }

    private func applyUnpinnedState(logMessage: String) {
        guard isPinned else {
            return
        }

        isPinned = false
        viewModel.setPanelPinned(false)
        viewModel.recordInternalEvent(logMessage)
    }

    private func resetOriginalConfiguration() {
        originalLevel = nil
        originalCollectionBehavior = nil
        originalMovableByBackground = nil
        originalHidesOnDeactivate = nil
    }
}

struct WindowEventObserver: NSViewRepresentable {
    let onResolveWindow: (NSWindow?) -> Void
    let onBecomeKey: () -> Void

    func makeNSView(context: Context) -> EventObservingView {
        let view = EventObservingView()
        view.onResolveWindow = onResolveWindow
        view.onBecomeKey = onBecomeKey
        return view
    }

    func updateNSView(_ nsView: EventObservingView, context: Context) {
        nsView.onResolveWindow = onResolveWindow
        nsView.onBecomeKey = onBecomeKey
    }
}

final class EventObservingView: NSView {
    var onResolveWindow: ((NSWindow?) -> Void)?
    var onBecomeKey: (() -> Void)?

    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil

        onResolveWindow?(window)

        guard let window else {
            return
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onBecomeKey?()
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }
}
