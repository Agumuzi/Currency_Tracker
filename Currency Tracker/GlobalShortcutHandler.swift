//
//  GlobalShortcutHandler.swift
//  Currency Tracker
//
//  Created by Codex on 4/13/26.
//

import AppKit
import Carbon
import SwiftUI

nonisolated struct GlobalShortcutDescriptor: Codable, Hashable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayKey: String

    var displayText: String {
        modifierSymbols + displayKey.uppercased()
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            return nil
        }

        let displayKey = ShortcutKeyNameResolver.displayName(
            for: event.keyCode,
            fallback: event.charactersIgnoringModifiers
        )
        guard !displayKey.isEmpty else {
            return nil
        }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = modifiers.carbonHotKeyModifiers
        self.displayKey = displayKey
    }

    func matches(event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode
            && event.modifierFlags
                .intersection([.command, .option, .control, .shift])
                .carbonHotKeyModifiers == carbonModifiers
    }

    private var modifierSymbols: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 {
            symbols += "⌃"
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            symbols += "⌥"
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            symbols += "⇧"
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            symbols += "⌘"
        }
        return symbols
    }
}

@MainActor
final class GlobalShortcutHandler {
    private let preferences: PreferencesStore
    private let coordinator: ConversionCoordinator
    private let popupPresenter: any LightweightPromptPaneling
    private let logHandler: @MainActor (RefreshLogEntry.Level, String) -> Void
    private let selectionReader = FocusedSelectionReader()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalKeyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var isHandlingHotKey = false

    init(
        preferences: PreferencesStore,
        coordinator: ConversionCoordinator,
        popupPresenter: any LightweightPromptPaneling,
        logHandler: @escaping @MainActor (RefreshLogEntry.Level, String) -> Void
    ) {
        self.preferences = preferences
        self.coordinator = coordinator
        self.popupPresenter = popupPresenter
        self.logHandler = logHandler
        installEventHandlerIfNeeded()
        observeApplicationActivation()
        refreshRegistration()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func refreshRegistration() {
        unregisterShortcut()

        guard let shortcut = preferences.textConversionShortcut else {
            removeGlobalKeyMonitor()
            logHandler(.info, "全局文本换算快捷键未设置")
            return
        }

        let hotKeyID = EventHotKeyID(signature: ShortcutHotKeySignature.value, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            logHandler(.info, "全局文本换算快捷键已注册：\(shortcut.displayText)")
        } else {
            hotKeyRef = nil
            logHandler(.warning, "全局文本换算快捷键注册失败：\(status)")
        }

        refreshGlobalKeyMonitor()
    }

    private func unregisterShortcut() {
        guard let hotKeyRef else {
            return
        }

        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let handler = Unmanaged<GlobalShortcutHandler>.fromOpaque(userData).takeUnretainedValue()
                handler.handle(event: event)
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
            logHandler(.warning, "全局文本换算快捷键事件监听安装失败：\(status)")
        }
    }

    private func handle(event: EventRef) {
        guard let shortcut = preferences.textConversionShortcut else {
            return
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == ShortcutHotKeySignature.value else {
            return
        }

        handleShortcutPress(shortcut)
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard let shortcut = preferences.textConversionShortcut,
              shortcut.matches(event: event) else {
            return
        }

        handleShortcutPress(shortcut)
    }

    private func handleShortcutPress(_ shortcut: GlobalShortcutDescriptor) {
        if isHandlingHotKey {
            return
        }

        isHandlingHotKey = true
        Task { @MainActor in
            defer { self.isHandlingHotKey = false }
            await triggerConversion(using: shortcut)
        }
    }

    private func observeApplicationActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshGlobalKeyMonitor()
            }
        }
    }

    private func refreshGlobalKeyMonitor() {
        removeGlobalKeyMonitor()

        guard preferences.textConversionShortcut != nil else {
            return
        }

        guard AXIsProcessTrusted() else {
            logHandler(.warning, "辅助功能权限未授予，备用快捷键监听暂不可用")
            return
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalKeyDown(event)
            }
        }

        if globalKeyMonitor != nil {
            logHandler(.info, "全局文本换算快捷键备用监听已启用")
        }
    }

    private func removeGlobalKeyMonitor() {
        guard let globalKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(globalKeyMonitor)
        self.globalKeyMonitor = nil
    }

    private func triggerConversion(using shortcut: GlobalShortcutDescriptor) async {
        logHandler(.info, "入口来源：全局快捷键（\(shortcut.displayText)）")

        let selectedText = await selectionReader.readSelectedText(log: logHandler)
        guard let selectedText, selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            logHandler(.warning, "全局快捷键触发失败：未检测到可读取的选中文本")
            await popupPresenter.showError(
                title: "未检测到选中文本",
                message: "请先选中金额或数字，再按下文本换算快捷键。"
            )
            return
        }

        await coordinator.handleSelectedText(selectedText, source: .globalShortcut)
    }
}

private enum ShortcutHotKeySignature {
    nonisolated static let value = OSType(UInt32(bigEndian: 0x4354524B))
}

private enum ShortcutKeyNameResolver {
    nonisolated private static let namedKeys: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Esc",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]

    nonisolated static func displayName(for keyCode: UInt16, fallback: String?) -> String {
        if let named = namedKeys[keyCode] {
            return named
        }

        let trimmedFallback = fallback?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        if !trimmedFallback.isEmpty {
            return trimmedFallback
        }

        return ""
    }
}

private extension NSEvent.ModifierFlags {
    nonisolated var carbonHotKeyModifiers: UInt32 {
        var result: UInt32 = 0

        if contains(.command) {
            result |= UInt32(cmdKey)
        }
        if contains(.option) {
            result |= UInt32(optionKey)
        }
        if contains(.control) {
            result |= UInt32(controlKey)
        }
        if contains(.shift) {
            result |= UInt32(shiftKey)
        }

        return result
    }
}

@MainActor
private final class FocusedSelectionReader {
    func readSelectedText(log: @MainActor (RefreshLogEntry.Level, String) -> Void) async -> String? {
        guard AXIsProcessTrusted() else {
            requestAccessibilityPromptIfNeeded(log: log)
            return nil
        }

        if let selectedText = selectedTextViaAccessibility(), !selectedText.isEmpty {
            log(.info, "全局快捷键通过辅助功能接口读取了选中文本")
            return selectedText
        }

        log(.info, "辅助功能接口未拿到选中文本，尝试通过复制动作读取")
        return await readSelectedTextViaCopyFallback(log: log)
    }

    private func selectedTextViaAccessibility() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard focusStatus == .success, let focusedElementRef else {
            return nil
        }

        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return nil
        }

        let focusedElement = focusedElementRef as! AXUIElement
        var selectedTextRef: CFTypeRef?
        let selectionStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )

        guard selectionStatus == .success,
              let selectedText = (selectedTextRef as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            return nil
        }

        return selectedText
    }

    private func readSelectedTextViaCopyFallback(
        log: @MainActor (RefreshLogEntry.Level, String) -> Void
    ) async -> String? {
        let pasteboard = NSPasteboard.general
        let previousSnapshot = PasteboardSnapshot.capture(from: pasteboard)
        let previousChangeCount = pasteboard.changeCount

        guard await sendCopyShortcut() else {
            previousSnapshot?.restore(to: pasteboard)
            log(.warning, "全局快捷键复制回退失败：无法发送复制按键")
            return nil
        }

        let maxAttempts = 15
        for _ in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: 60_000_000)

            guard pasteboard.changeCount != previousChangeCount else {
                continue
            }

            if let copiedText = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !copiedText.isEmpty {
                log(.info, "全局快捷键通过复制动作读取了选中文本")
                previousSnapshot?.restore(to: pasteboard)
                return copiedText
            }
        }

        previousSnapshot?.restore(to: pasteboard)
        log(.warning, "全局快捷键复制回退未读取到选中文本")
        return nil
    }

    private func sendCopyShortcut() async -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
            ?? CGEventSource(stateID: .hidSystemState)

        guard let source,
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 25_000_000)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func requestAccessibilityPromptIfNeeded(
        log: @MainActor (RefreshLogEntry.Level, String) -> Void
    ) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) == false {
            log(.warning, "系统可能尚未授予辅助功能权限，已请求系统弹出授权提示")
        }
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot? {
        let snapshotItems = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { partialResult, type in
                if let data = item.data(forType: type) {
                    partialResult[type] = data
                }
            }
        }

        return PasteboardSnapshot(items: snapshotItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

struct GlobalShortcutRecorderView: View {
    let shortcut: GlobalShortcutDescriptor?
    let onChange: (GlobalShortcutDescriptor?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var helperText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isRecording {
                    Button("按下快捷键…") {
                        toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)
                } else if let shortcut {
                    Button(shortcut.displayText) {
                        toggleRecording()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("录制快捷键") {
                        toggleRecording()
                    }
                    .buttonStyle(.bordered)
                }

                if shortcut != nil {
                    Button("清除") {
                        stopRecording()
                        helperText = nil
                        onChange(nil)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let helperText {
                Text(helperText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear {
            stopRecording()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            helperText = nil
            return
        }

        helperText = String(localized: "按下包含修饰键的组合；按 Esc 取消。")
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else {
                return event
            }

            if event.keyCode == 53 {
                stopRecording()
                helperText = nil
                return nil
            }

            guard let shortcut = GlobalShortcutDescriptor(event: event) else {
                helperText = String(localized: "快捷键至少要包含一个修饰键。")
                return nil
            }

            stopRecording()
            helperText = nil
            onChange(shortcut)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
