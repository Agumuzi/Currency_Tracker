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
    private var pinnedWindowController: NSWindowController?
    private var pinnedWindowFactory: (() -> NSWindow)?
    private var suppressPinnedWindowCloseCallback = false
    private var originalLevel: NSWindow.Level?
    private var originalCollectionBehavior: NSWindow.CollectionBehavior?
    private var originalMovableByBackground: Bool?
    private var originalHidesOnDeactivate: Bool?
    var isPinned = false

    private let viewModel: ExchangePanelViewModel

    init(viewModel: ExchangePanelViewModel) {
        self.viewModel = viewModel
    }

    func configurePinnedWindowFactory(_ factory: @escaping () -> NSWindow) {
        pinnedWindowFactory = factory
    }

    func registerMenuBarWindow(_ window: NSWindow?) {
        guard let window else {
            return
        }

        menuBarWindow = window

        if isPinned, pinnedWindowController == nil {
            applyPinnedConfiguration(to: window)
        }
    }

    func dismissTransientMenuWindowIfNeeded(_ window: NSWindow?) {
        guard isPinned,
              let window,
              window != pinnedWindowController?.window else {
            return
        }

        window.orderOut(nil)
    }

    func togglePinnedPanel(from sourceWindow: NSWindow?) {
        if isPinned {
            unpin()
        } else {
            pin(window: sourceWindow ?? menuBarWindow)
        }
    }

    private func pin(window: NSWindow?) {
        if let pinnedWindow = ensurePinnedWindow() {
            positionPinnedWindowIfNeeded(pinnedWindow, relativeTo: window)
            pinnedWindow.makeKeyAndOrderFront(nil)
            window?.orderOut(nil)
        } else {
            guard let window else {
                return
            }

            menuBarWindow = window
            captureOriginalConfigurationIfNeeded(from: window)
            applyPinnedConfiguration(to: window)
        }

        applyPinnedState(logMessage: "汇率面板已锁定，自动刷新已暂停")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func unpin() {
        if let pinnedWindowController {
            suppressPinnedWindowCloseCallback = true
            pinnedWindowController.close()
            suppressPinnedWindowCloseCallback = false
            self.pinnedWindowController = nil
            applyUnpinnedState(logMessage: "汇率面板已解除锁定，自动刷新已恢复")
            return
        }

        guard let window = menuBarWindow else {
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

        applyUnpinnedState(logMessage: "汇率面板已解除锁定，自动刷新已恢复")
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == pinnedWindowController?.window else {
            return
        }

        pinnedWindowController = nil

        if suppressPinnedWindowCloseCallback {
            return
        }

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

    private func ensurePinnedWindow() -> NSWindow? {
        if let window = pinnedWindowController?.window {
            return window
        }

        guard let pinnedWindowFactory else {
            return nil
        }

        let window = pinnedWindowFactory()
        window.delegate = self
        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = false
        pinnedWindowController = controller
        return window
    }

    private func positionPinnedWindowIfNeeded(_ pinnedWindow: NSWindow, relativeTo sourceWindow: NSWindow?) {
        guard pinnedWindow.isVisible == false else {
            return
        }

        guard let sourceWindow else {
            pinnedWindow.center()
            return
        }

        let sourceFrame = sourceWindow.frame
        let visibleFrame = sourceWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? sourceFrame
        let targetOrigin = NSPoint(
            x: min(
                max(sourceFrame.midX - (pinnedWindow.frame.width / 2), visibleFrame.minX + 16),
                visibleFrame.maxX - pinnedWindow.frame.width - 16
            ),
            y: min(
                max(sourceFrame.maxY - pinnedWindow.frame.height + 24, visibleFrame.minY + 16),
                visibleFrame.maxY - pinnedWindow.frame.height - 16
            )
        )

        pinnedWindow.setFrameOrigin(targetOrigin)
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
}

@MainActor
final class DetachedPinnedPanelWindow: NSPanel {
    init(contentViewController: NSViewController, contentSize: NSSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.contentViewController = contentViewController
        title = "Currency Tracker"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        setContentSize(contentSize)
        center()
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
