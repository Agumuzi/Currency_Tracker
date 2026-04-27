//
//  SoftwareUpdatePromptWindow.swift
//  Currency Tracker
//
//  Created by Codex on 4/24/26.
//

import AppKit
import SwiftUI

@MainActor
final class SoftwareUpdateWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?

    func show(
        updateInfo: SoftwareUpdateInfo,
        currentVersion: String = SoftwareUpdateChecker.currentVersion(),
        preferences: PreferencesStore
    ) {
        let rootView = SoftwareUpdatePromptView(
            updateInfo: updateInfo,
            currentVersion: currentVersion,
            preferences: preferences,
            onSkip: { [weak self, weak preferences] in
                preferences?.skipUpdate(version: updateInfo.version)
                self?.close()
            },
            onRemindLater: { [weak self] in
                self?.close()
            },
            onPrepareUpdate: { [weak self] progressHandler in
                await self?.prepareUpdate(
                    for: updateInfo,
                    progressHandler: progressHandler
                ) ?? .failed(String(localized: "下载失败，请稍后重试"))
            },
            onInstallAndRelaunch: { preparedUpdate in
                Self.installAndRelaunch(preparedUpdate)
            },
            onCleanup: { preparedUpdate in
                SoftwareUpdateInstaller.cleanup(preparedUpdate)
            }
        )

        if windowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
            window.identifier = NSUserInterfaceItemIdentifier("currency-tracker-update-window")
            window.delegate = self
            window.title = String(localized: "软件更新")
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 760, height: 520))
            window.minSize = NSSize(width: 680, height: 460)
            window.center()
            windowController = NSWindowController(window: window)
        } else if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: rootView)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        windowController?.window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == windowController?.window else {
            return
        }

        windowController?.window?.contentViewController = nil
    }

    private func prepareUpdate(
        for updateInfo: SoftwareUpdateInfo,
        progressHandler: @escaping @MainActor (SoftwareUpdatePreparationStep) -> Void
    ) async -> SoftwareUpdatePreparationResult {
        do {
            let preparedUpdate = try await SoftwareUpdateInstaller.prepareUpdate(
                for: updateInfo,
                progressHandler: progressHandler
            )
            return .prepared(
                preparedUpdate,
                String(localized: "更新已准备就绪。点击“更新并重启应用”完成安装。")
            )
        } catch {
            return .failed(Self.updatePreparationMessage(for: error))
        }
    }

    @MainActor
    private static func installAndRelaunch(_ preparedUpdate: PreparedSoftwareUpdate) -> String? {
        do {
            try SoftwareUpdateInstaller.installAndRelaunch(preparedUpdate: preparedUpdate)
            NSApplication.shared.terminate(nil)
            return nil
        } catch {
            return String(localized: "无法启动安装器，请稍后重试")
        }
    }

    private static func updatePreparationMessage(for error: Error) -> String {
        switch error as? SoftwareUpdateInstallationError {
        case .missingDownloadURL:
            return String(localized: "没有找到可下载的更新包")
        case .downloadFailed:
            return String(localized: "下载失败，请稍后重试")
        case .extractionFailed:
            return String(localized: "更新包无法解压，请稍后重试")
        case .applicationNotFound:
            return String(localized: "更新包中没有找到 Currency Tracker.app")
        case .bundleIdentifierMismatch:
            return String(localized: "更新包与当前应用不匹配")
        case .versionNotNewer:
            return String(localized: "更新包版本不高于当前版本")
        case .installerLaunchFailed:
            return String(localized: "无法启动安装器，请稍后重试")
        case .missingChecksum:
            return String(localized: "更新包缺少校验文件")
        case .checksumDownloadFailed:
            return String(localized: "更新校验文件无法读取，请稍后重试")
        case .checksumMismatch:
            return String(localized: "更新包校验失败，请稍后重试")
        case nil:
            return String(localized: "下载失败，请稍后重试")
        }
    }
}

@MainActor
final class AutomaticSoftwareUpdateCoordinator {
    private let preferences: PreferencesStore
    private let updateWindowController: SoftwareUpdateWindowController
    private let isRunningUITests: Bool
    private let minimumCheckInterval: TimeInterval
    private var checkTask: Task<Void, Never>?

    init(
        preferences: PreferencesStore,
        updateWindowController: SoftwareUpdateWindowController,
        isRunningUITests: Bool,
        minimumCheckInterval: TimeInterval = 60 * 60 * 24
    ) {
        self.preferences = preferences
        self.updateWindowController = updateWindowController
        self.isRunningUITests = isRunningUITests
        self.minimumCheckInterval = minimumCheckInterval
    }

    func checkIfNeeded() {
        guard !isRunningUITests,
              preferences.automaticUpdateChecksEnabled,
              checkTask == nil else {
            return
        }

        if let lastCheck = preferences.lastAutomaticUpdateCheckAt,
           Date().timeIntervalSince(lastCheck) < minimumCheckInterval {
            return
        }

        checkTask = Task { [weak self] in
            await self?.performCheck()
        }
    }

    private func performCheck() async {
        defer {
            checkTask = nil
        }

        do {
            let latestInfo = try await SoftwareUpdateChecker.fetchLatestRelease()
            preferences.setLastAutomaticUpdateCheckAt(.now)

            guard latestInfo.isNewer(than: SoftwareUpdateChecker.currentVersion()),
                  preferences.skippedUpdateVersion != latestInfo.version else {
                return
            }

            updateWindowController.show(updateInfo: latestInfo, preferences: preferences)
        } catch {
            preferences.setLastAutomaticUpdateCheckAt(.now)
        }
    }
}

private enum SoftwareUpdatePreparationResult {
    case prepared(PreparedSoftwareUpdate, String)
    case failed(String)
}

private struct SoftwareUpdatePromptView: View {
    let updateInfo: SoftwareUpdateInfo
    let currentVersion: String
    let preferences: PreferencesStore
    let onSkip: () -> Void
    let onRemindLater: () -> Void
    let onPrepareUpdate: (@escaping @MainActor (SoftwareUpdatePreparationStep) -> Void) async -> SoftwareUpdatePreparationResult
    let onInstallAndRelaunch: (PreparedSoftwareUpdate) async -> String?
    let onCleanup: (PreparedSoftwareUpdate?) -> Void
    @State private var isPreparingUpdate = false
    @State private var isInstallingUpdate = false
    @State private var preparedUpdate: PreparedSoftwareUpdate?
    @State private var preparationStep: SoftwareUpdatePreparationStep?
    @State private var updateMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            releaseNotesCard
            footer
        }
        .padding(.horizontal, 34)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            guard isInstallingUpdate == false else {
                return
            }

            onCleanup(preparedUpdate)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 9) {
                Text("新版的 Currency Tracker 已经发布")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(format: String(localized: "Currency Tracker %@ 可供下载，您现在的版本是 %@。"), updateInfo.version, currentVersion))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
    }

    private var releaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(releaseTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.vertical, showsIndicators: true) {
                Text(releaseNotesText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 220, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(
                "以后自动检查更新",
                isOn: Binding(
                    get: { preferences.automaticUpdateChecksEnabled },
                    set: { preferences.setAutomaticUpdateChecksEnabled($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 13, weight: .semibold, design: .rounded))

            Text("安装需要 macOS 权限确认时，系统会自动弹出授权窗口。")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if isPreparingUpdate || isInstallingUpdate {
                ProgressView(
                    value: isInstallingUpdate ? 1 : (preparationStep?.progress ?? 0.08),
                    total: 1
                )
                .progressViewStyle(.linear)
                .controlSize(.small)
            }

            if let updateMessage {
                Text(updateMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Button("跳过这个版本") {
                    onCleanup(preparedUpdate)
                    onSkip()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minWidth: 140)

                Spacer()

                Button("稍后提醒我") {
                    onCleanup(preparedUpdate)
                    onRemindLater()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minWidth: 140)

                Button(primaryActionTitle) {
                    Task {
                        await runPrimaryUpdateAction()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isPreparingUpdate || isInstallingUpdate)
                .keyboardShortcut(.defaultAction)
                .frame(minWidth: 150)
            }
        }
    }

    private var primaryActionTitle: LocalizedStringKey {
        if isInstallingUpdate {
            return "正在启动安装…"
        }

        if isPreparingUpdate {
            return "正在准备更新…"
        }

        if preparedUpdate != nil {
            return "更新并重启应用"
        }

        return "下载更新"
    }

    @MainActor
    private func runPrimaryUpdateAction() async {
        if let preparedUpdate {
            isInstallingUpdate = true
            updateMessage = String(localized: "正在启动安装器…")
            if let failureMessage = await onInstallAndRelaunch(preparedUpdate) {
                updateMessage = failureMessage
                isInstallingUpdate = false
            }
            return
        }

        isPreparingUpdate = true
        updateMessage = nil
        preparationStep = .downloading

        switch await onPrepareUpdate({ step in
            preparationStep = step
            updateMessage = step.message
        }) {
        case .prepared(let update, let message):
            preparedUpdate = update
            updateMessage = message
        case .failed(let message):
            updateMessage = message
        }

        isPreparingUpdate = false
        preparationStep = nil
    }

    private var releaseTitle: String {
        guard let title = updateInfo.title else {
            return String(format: String(localized: "版本 %@：更新说明"), updateInfo.version)
        }

        if title.localizedStandardContains(updateInfo.version) {
            return title
        }

        return "\(updateInfo.version): \(title)"
    }

    private var releaseNotesText: String {
        updateInfo.releaseNotes ?? String(localized: "打开 GitHub Releases 查看完整更新说明。")
    }
}
