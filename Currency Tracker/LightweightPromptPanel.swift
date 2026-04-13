//
//  LightweightPromptPanel.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import AppKit
import Foundation
import SwiftUI

@MainActor
protocol LightweightPromptPaneling: AnyObject {
    func chooseCurrencyForAmbiguousSymbol(
        amount: Decimal,
        symbol: String,
        candidates: [String],
        targetCurrencyCode: String
    ) async -> String?

    func chooseCurrencyForManualInput(
        amount: Decimal,
        targetCurrencyCode: String
    ) async -> String?

    func chooseAmountInterpretation(
        rawText: String,
        options: [MoneyParsing.AmountOption]
    ) async -> Decimal?

    func showResult(_ presentation: ConversionPresentation) async -> Bool

    func showError(title: String, message: String) async
}

@MainActor
final class LightweightPromptPanel: LightweightPromptPaneling {
    private var sessions: [UUID: AnyObject] = [:]

    func chooseCurrencyForAmbiguousSymbol(
        amount: Decimal,
        symbol: String,
        candidates: [String],
        targetCurrencyCode: String
    ) async -> String? {
        let choices = CurrencyDisambiguation.choices(for: candidates)
        return await present(size: NSSize(width: 360, height: 250)) { resolve in
            AmbiguousCurrencyPromptView(
                amountText: ServiceConversionFormatting.sourceAmount(amount),
                symbol: symbol,
                targetCurrencyCode: targetCurrencyCode,
                choices: choices,
                onSelect: { resolve($0) },
                onCancel: { resolve(nil) }
            )
        }
    }

    func chooseCurrencyForManualInput(
        amount: Decimal,
        targetCurrencyCode: String
    ) async -> String? {
        await present(size: NSSize(width: 400, height: 288)) { resolve in
            ManualCurrencyPromptView(
                amountText: ServiceConversionFormatting.sourceAmount(amount),
                targetCurrencyCode: targetCurrencyCode,
                onSelect: { resolve($0) },
                onCancel: { resolve(nil) }
            )
        }
    }

    func chooseAmountInterpretation(
        rawText: String,
        options: [MoneyParsing.AmountOption]
    ) async -> Decimal? {
        await present(size: NSSize(width: 400, height: 248)) { resolve in
            AmountInterpretationPromptView(
                rawText: rawText,
                options: options,
                onSelect: { resolve($0) },
                onCancel: { resolve(nil) }
            )
        }
    }

    func showResult(_ presentation: ConversionPresentation) async -> Bool {
        let result = await present(size: NSSize(width: 360, height: 194)) { resolve in
            ResultPromptView(
                expressionText: presentation.expressionText,
                onDismiss: { resolve(true) }
            )
        }

        return result ?? false
    }

    func showError(title: String, message: String) async {
        let _: Bool? = await present(size: NSSize(width: 360, height: 208)) { resolve in
            ErrorPromptView(
                title: title,
                message: message,
                onDismiss: { resolve(true) }
            )
        }
    }

    private func present<Result, Content: View>(
        size: NSSize,
        @ViewBuilder content: @escaping (@escaping (Result?) -> Void) -> Content
    ) async -> Result? {
        await withCheckedContinuation { continuation in
            let session = PromptSession<Result>(
                size: size,
                onFinish: { [weak self] id in
                    self?.sessions.removeValue(forKey: id)
                }
            )

            sessions[session.id] = session
            let rootView = content { [weak session] result in
                session?.resolve(result)
            }
            session.install(rootView: rootView)
            activateForPrompt()
            session.present()
            session.setContinuation(continuation)
        }
    }

    private func activateForPrompt() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private protocol PromptSessionProtocol: AnyObject {
    var id: UUID { get }
}

@MainActor
private final class PromptSession<Result>: NSObject, NSWindowDelegate, PromptSessionProtocol {
    let id = UUID()

    private let panel: NSPanel
    private let contentSize: NSSize
    private let onFinish: (UUID) -> Void
    private var continuation: CheckedContinuation<Result?, Never>?
    private var didResolve = false

    init(size: NSSize, onFinish: @escaping (UUID) -> Void) {
        self.contentSize = size
        self.onFinish = onFinish
        self.panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentMinSize = size
        panel.minSize = size
        panel.maxSize = size
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.setContentSize(size)
    }

    func install<Content: View>(rootView: Content) {
        let hostingView = NSHostingView(
            rootView: AnyView(
                rootView
                    .frame(width: contentSize.width, height: contentSize.height)
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.frame = CGRect(origin: .zero, size: contentSize)

        let containerView = NSView(frame: CGRect(origin: .zero, size: contentSize))
        containerView.translatesAutoresizingMaskIntoConstraints = true
        containerView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        panel.contentViewController = nil
        panel.contentView = containerView
        panel.setContentSize(contentSize)
    }

    func setContinuation(_ continuation: CheckedContinuation<Result?, Never>) {
        self.continuation = continuation
    }

    func present() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
    }

    func resolve(_ result: Result?) {
        guard didResolve == false else {
            return
        }

        didResolve = true
        continuation?.resume(returning: result)
        continuation = nil
        panel.close()
        onFinish(id)
    }

    func windowWillClose(_ notification: Notification) {
        guard didResolve == false else {
            return
        }

        didResolve = true
        continuation?.resume(returning: nil)
        continuation = nil
        onFinish(id)
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let x = min(max(mouseLocation.x - (panel.frame.width / 2), visibleFrame.minX + 16), visibleFrame.maxX - panel.frame.width - 16)
        let y = min(max(mouseLocation.y - (panel.frame.height / 2), visibleFrame.minY + 16), visibleFrame.maxY - panel.frame.height - 16)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct PromptCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(nsColor: .underPageBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )

            content
                .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AmbiguousCurrencyPromptView: View {
    let amountText: String
    let symbol: String
    let targetCurrencyCode: String
    let choices: [CurrencyChoice]
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        PromptCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("检测到金额：\(amountText)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text("符号 “\(symbol)” 存在歧义，请选择原始货币")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("结果将换算为 \(targetCurrencyCode)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(choices) { choice in
                        Button {
                            onSelect(choice.code)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(choice.code)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                Text(choice.name)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Spacer()

                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
        }
    }
}

private struct ManualCurrencyPromptView: View {
    let amountText: String
    let targetCurrencyCode: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var input = ""
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        PromptCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("检测到金额：\(amountText)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text("输入原始货币代码或名称")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("结果将换算为 \(targetCurrencyCode)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("例如 USD / 美元 / Turkish Lira / 土耳其里拉", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        submit()
                    }

                HStack(spacing: 8) {
                    ForEach(CurrencyInputNormalization.commonShortcutCodes, id: \.self) { code in
                        Button(code) {
                            onSelect(code)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.74, green: 0.20, blue: 0.18))
                }

                HStack {
                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium, design: .rounded))

                    Spacer()

                    Button("继续") {
                        submit()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .task {
                isInputFocused = true
            }
        }
    }

    private func submit() {
        guard let code = CurrencyInputNormalization.normalize(input) else {
            errorMessage = "未识别该币种，请输入标准代码或常见名称。"
            return
        }

        errorMessage = nil
        onSelect(code)
    }
}

private struct AmountInterpretationPromptView: View {
    let rawText: String
    let options: [MoneyParsing.AmountOption]
    let onSelect: (Decimal) -> Void
    let onCancel: () -> Void

    var body: some View {
        PromptCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("金额存在歧义")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text("“\(rawText)” 可能有两种含义，请确认原始数值")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    ForEach(options) { option in
                        Button {
                            onSelect(option.value)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ServiceConversionFormatting.sourceAmount(option.value))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    Text(option.description)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Spacer()

                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
        }
    }
}

private struct ResultPromptView: View {
    let expressionText: String
    let onDismiss: () -> Void

    @State private var didAutoDismiss = false

    var body: some View {
        PromptCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("换算结果")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text(expressionText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Spacer()

                    Button("关闭") {
                        dismissIfNeeded()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            dismissIfNeeded()
        }
    }

    private func dismissIfNeeded() {
        guard didAutoDismiss == false else {
            return
        }

        didAutoDismiss = true
        onDismiss()
    }
}

private struct ErrorPromptView: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        PromptCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()

                    Button("关闭") {
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}
