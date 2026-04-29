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
    private var pinnedWindow: NSWindow?
    private var originalLevel: NSWindow.Level?
    private var originalCollectionBehavior: NSWindow.CollectionBehavior?
    private var originalMovableByBackground: Bool?
    private var originalHidesOnDeactivate: Bool?
    private var pinnedContentProvider: ((PanelWindowController) -> AnyView)?
    private var usesDedicatedPinnedWindow = false
    var isPinned = false

    private let viewModel: ExchangePanelViewModel

    init(viewModel: ExchangePanelViewModel) {
        self.viewModel = viewModel
    }

    func configurePinnedContent(_ provider: @escaping (PanelWindowController) -> AnyView) {
        pinnedContentProvider = provider
    }

    func registerMenuBarWindow(_ window: NSWindow?) {
        guard let window else {
            return
        }

        if isPinned {
            if let pinnedWindow {
                if window !== pinnedWindow {
                    window.orderOut(nil)
                    pinnedWindow.makeKeyAndOrderFront(nil)
                    pinnedWindow.orderFrontRegardless()
                }
                return
            }

            if pinnedWindow == nil {
                pinnedWindow = window
                usesDedicatedPinnedWindow = false
                captureOriginalConfigurationIfNeeded(from: window)
                applyPinnedConfiguration(to: window)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
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

        if let pinnedContentProvider {
            presentDedicatedPinnedWindow(from: window, content: pinnedContentProvider(self))
            return
        }

        menuBarWindow = window
        pinnedWindow = window
        usesDedicatedPinnedWindow = false
        captureOriginalConfigurationIfNeeded(from: window)
        applyPinnedConfiguration(to: window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        applyPinnedState(logMessage: "汇率面板已锁定，自动刷新已暂停")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func unpin() {
        guard let window = pinnedWindow ?? menuBarWindow else {
            applyUnpinnedState(logMessage: "汇率面板已解除锁定，自动刷新已恢复")
            return
        }

        if usesDedicatedPinnedWindow {
            pinnedWindow = nil
            usesDedicatedPinnedWindow = false
            window.close()
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
        usesDedicatedPinnedWindow = false
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = true

        if let panel = window as? NSPanel {
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
        }
    }

    private func presentDedicatedPinnedWindow(from sourceWindow: NSWindow, content: AnyView) {
        menuBarWindow = sourceWindow

        let contentSize = resolvedPinnedContentSize(from: sourceWindow)
        let frame = resolvedPinnedFrame(contentSize: contentSize, sourceWindow: sourceWindow)
        let panel = PinnedExchangeRatePanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.identifier = NSUserInterfaceItemIdentifier("currency-tracker-pinned-panel")
        panel.delegate = self
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 408, height: 320)
        panel.maxSize = NSSize(width: 560, height: max(760, contentSize.height))
        pinnedWindow?.close()
        pinnedWindow = panel
        usesDedicatedPinnedWindow = true
        sourceWindow.orderOut(nil)
        applyPinnedState(logMessage: "汇率面板已锁定，自动刷新已暂停")
        panel.contentViewController = NSHostingController(rootView: content)
        panel.setContentSize(contentSize)
        panel.setFrame(frame, display: false)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func resolvedPinnedContentSize(from sourceWindow: NSWindow) -> NSSize {
        let sourceSize = sourceWindow.contentLayoutRect.size
        if sourceSize.width > 0, sourceSize.height > 0 {
            return sourceSize
        }

        let fallbackSize = sourceWindow.frame.size
        if fallbackSize.width > 0, fallbackSize.height > 0 {
            return fallbackSize
        }

        return NSSize(width: 408, height: 620)
    }

    private func resolvedPinnedFrame(contentSize: NSSize, sourceWindow: NSWindow) -> NSRect {
        let visibleFrame = screen(for: sourceWindow).visibleFrame
        let sourceFrame = sourceWindow.frame
        let edgeMargin: CGFloat = 8
        let topMargin: CGFloat = 2
        let x = clamped(
            sourceFrame.minX,
            lower: visibleFrame.minX + edgeMargin,
            upper: max(visibleFrame.minX + edgeMargin, visibleFrame.maxX - contentSize.width - edgeMargin)
        )
        let sourceTopEdge = sourceFrame.maxY
        let sourceTopEdgeLooksUsable = sourceTopEdge >= visibleFrame.maxY - 120
            && sourceTopEdge <= visibleFrame.maxY + 80
        let targetTopEdge = sourceTopEdgeLooksUsable
            ? min(sourceTopEdge, visibleFrame.maxY - topMargin)
            : visibleFrame.maxY - topMargin
        let y = clamped(
            targetTopEdge - contentSize.height,
            lower: visibleFrame.minY + edgeMargin,
            upper: max(visibleFrame.minY + edgeMargin, visibleFrame.maxY - contentSize.height - topMargin)
        )

        return NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height)
    }

    private func screen(for sourceWindow: NSWindow) -> NSScreen {
        if let screen = sourceWindow.screen {
            return screen
        }

        let sourceFrame = sourceWindow.frame
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(sourceFrame) }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
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

private final class PinnedExchangeRatePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

struct WindowEventObserver: NSViewRepresentable {
    let onResolveWindow: (NSWindow?) -> Void
    let onResize: (CGSize) -> Void
    let onBecomeKey: () -> Void

    func makeNSView(context: Context) -> EventObservingView {
        let view = EventObservingView()
        view.onResolveWindow = onResolveWindow
        view.onResize = onResize
        view.onBecomeKey = onBecomeKey
        return view
    }

    func updateNSView(_ nsView: EventObservingView, context: Context) {
        nsView.onResolveWindow = onResolveWindow
        nsView.onResize = onResize
        nsView.onBecomeKey = onBecomeKey
    }
}

final class EventObservingView: NSView {
    var onResolveWindow: ((NSWindow?) -> Void)?
    var onResize: ((CGSize) -> Void)?
    var onBecomeKey: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()

        onResolveWindow?(window)

        guard let window else {
            return
        }

        onResize?(window.contentLayoutRect.size)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.onBecomeKey?()
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let window else {
                return
            }

            self?.onResize?(window.contentLayoutRect.size)
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
