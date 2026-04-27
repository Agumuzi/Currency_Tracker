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
            onDownload: { [weak self] in
                await self?.downloadUpdate(for: updateInfo) ?? String(localized: "下载失败，请稍后重试")
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

    private func downloadUpdate(for updateInfo: SoftwareUpdateInfo) async -> String {
        guard let downloadURL = updateInfo.downloadURL else {
            NSWorkspace.shared.open(updateInfo.releaseURL)
            return String(localized: "已打开发布页面")
        }

        do {
            let (temporaryURL, _) = try await URLSession.shared.download(from: downloadURL)
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let fileURL = downloadsURL.appendingPathComponent("Currency-Tracker-\(updateInfo.version).zip")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return String(format: String(localized: "已下载到 %@"), fileURL.lastPathComponent)
        } catch {
            NSWorkspace.shared.open(updateInfo.downloadURL ?? updateInfo.releaseURL)
            return String(localized: "下载失败，已打开发布页面")
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

private struct SoftwareUpdatePromptView: View {
    let updateInfo: SoftwareUpdateInfo
    let currentVersion: String
    let preferences: PreferencesStore
    let onSkip: () -> Void
    let onRemindLater: () -> Void
    let onDownload: () async -> String
    @State private var isDownloading = false
    @State private var downloadMessage: String?

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

            if isDownloading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }

            if let downloadMessage {
                Text(downloadMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Button("跳过这个版本") {
                    onSkip()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minWidth: 140)

                Spacer()

                Button("稍后提醒我") {
                    onRemindLater()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minWidth: 140)

                Button("下载更新") {
                    Task {
                        isDownloading = true
                        downloadMessage = nil
                        downloadMessage = await onDownload()
                        isDownloading = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isDownloading)
                .keyboardShortcut(.defaultAction)
                .frame(minWidth: 150)
            }
        }
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
