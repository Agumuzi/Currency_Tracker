//
//  SoftwareUpdateInstaller.swift
//  Currency Tracker
//
//  Created by Codex on 4/27/26.
//

import Foundation

nonisolated struct PreparedSoftwareUpdate: Equatable, Sendable {
    let version: String
    let downloadedArchiveURL: URL
    let extractedApplicationURL: URL
    let workingDirectoryURL: URL
}

nonisolated enum SoftwareUpdateInstallationError: Error, Equatable {
    case missingDownloadURL
    case downloadFailed
    case extractionFailed
    case applicationNotFound
    case bundleIdentifierMismatch
    case versionNotNewer
    case installerLaunchFailed
}

nonisolated enum SoftwareUpdateInstaller {
    static func prepareUpdate(
        for updateInfo: SoftwareUpdateInfo,
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        currentBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        currentVersion: String = SoftwareUpdateChecker.currentVersion()
    ) async throws -> PreparedSoftwareUpdate {
        guard let downloadURL = updateInfo.downloadURL else {
            throw SoftwareUpdateInstallationError.missingDownloadURL
        }

        let workingDirectoryURL = try createWorkingDirectory(for: updateInfo.version, fileManager: fileManager)
        let archiveURL = workingDirectoryURL.appendingPathComponent("Currency-Tracker-\(updateInfo.version).zip")
        let extractionURL = workingDirectoryURL.appendingPathComponent("extracted", isDirectory: true)

        do {
            let (temporaryURL, _) = try await session.download(from: downloadURL)
            if fileManager.fileExists(atPath: archiveURL.path) {
                try fileManager.removeItem(at: archiveURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: archiveURL)
        } catch {
            try? fileManager.removeItem(at: workingDirectoryURL)
            throw SoftwareUpdateInstallationError.downloadFailed
        }

        do {
            try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
            try await runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, extractionURL.path]
            )
        } catch {
            try? fileManager.removeItem(at: workingDirectoryURL)
            throw SoftwareUpdateInstallationError.extractionFailed
        }

        guard let appURL = findExtractedApplication(in: extractionURL, fileManager: fileManager) else {
            try? fileManager.removeItem(at: workingDirectoryURL)
            throw SoftwareUpdateInstallationError.applicationNotFound
        }

        try validateExtractedApplication(
            at: appURL,
            updateInfo: updateInfo,
            currentBundleIdentifier: currentBundleIdentifier,
            currentVersion: currentVersion
        )

        return PreparedSoftwareUpdate(
            version: updateInfo.version,
            downloadedArchiveURL: archiveURL,
            extractedApplicationURL: appURL,
            workingDirectoryURL: workingDirectoryURL
        )
    }

    @MainActor
    static func installAndRelaunch(
        preparedUpdate: PreparedSoftwareUpdate,
        currentApplicationURL: URL = defaultInstallationTargetURL(),
        currentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        fileManager: FileManager = .default
    ) throws {
        let scriptURL = preparedUpdate.workingDirectoryURL.appendingPathComponent("install-update.sh")
        let script = installerScript(
            currentApplicationURL: currentApplicationURL,
            newApplicationURL: preparedUpdate.extractedApplicationURL,
            workingDirectoryURL: preparedUpdate.workingDirectoryURL,
            processIdentifier: currentProcessIdentifier
        )

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            if canWriteToApplicationLocation(currentApplicationURL, fileManager: fileManager) {
                try runInstallerWithoutAuthorization(scriptURL: scriptURL)
            } else {
                try runInstallerWithAuthorization(scriptURL: scriptURL)
            }
        } catch {
            throw SoftwareUpdateInstallationError.installerLaunchFailed
        }
    }

    static func defaultInstallationTargetURL(bundleURL: URL = Bundle.main.bundleURL) -> URL {
        if bundleURL.path.contains("/AppTranslocation/") {
            return URL(fileURLWithPath: "/Applications/Currency Tracker.app")
        }

        return bundleURL
    }

    static func cleanup(_ preparedUpdate: PreparedSoftwareUpdate?, fileManager: FileManager = .default) {
        guard let preparedUpdate else {
            return
        }

        try? fileManager.removeItem(at: preparedUpdate.workingDirectoryURL)
    }

    static func findExtractedApplication(in directoryURL: URL, fileManager: FileManager = .default) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else {
                continue
            }

            if url.lastPathComponent == "Currency Tracker.app" {
                return url
            }
        }

        return nil
    }

    static func validateExtractedApplication(
        at applicationURL: URL,
        updateInfo: SoftwareUpdateInfo,
        currentBundleIdentifier: String?,
        currentVersion: String = SoftwareUpdateChecker.currentVersion()
    ) throws {
        guard let bundle = Bundle(url: applicationURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier == currentBundleIdentifier else {
            throw SoftwareUpdateInstallationError.bundleIdentifierMismatch
        }

        let bundledVersion = SoftwareUpdateChecker.currentVersion(bundle: bundle)
        guard SoftwareVersionComparator.compare(bundledVersion, currentVersion) == .orderedDescending,
              SoftwareVersionComparator.compare(bundledVersion, updateInfo.version) == .orderedSame else {
            throw SoftwareUpdateInstallationError.versionNotNewer
        }
    }

    private static func createWorkingDirectory(for version: String, fileManager: FileManager) throws -> URL {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = cachesURL
            .appendingPathComponent("Currency Tracker", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent("\(version)-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private static func runProcess(executableURL: URL, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SoftwareUpdateInstallationError.extractionFailed
        }
    }

    @MainActor
    private static func canWriteToApplicationLocation(_ currentApplicationURL: URL, fileManager: FileManager) -> Bool {
        let parentURL = currentApplicationURL.deletingLastPathComponent()
        return fileManager.isWritableFile(atPath: parentURL.path)
    }

    @MainActor
    private static func runInstallerWithoutAuthorization(scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
    }

    @MainActor
    private static func runInstallerWithAuthorization(scriptURL: URL) throws {
        let shellCommand = "/bin/zsh \(scriptURL.path.shellQuoted) >/dev/null 2>&1 &"
        let appleScriptSource = "do shell script \"\(shellCommand.appleScriptEscaped)\" with administrator privileges"
        var error: NSDictionary?
        let result = NSAppleScript(source: appleScriptSource)?.executeAndReturnError(&error)

        if result == nil || error != nil {
            throw SoftwareUpdateInstallationError.installerLaunchFailed
        }
    }

    private static func installerScript(
        currentApplicationURL: URL,
        newApplicationURL: URL,
        workingDirectoryURL: URL,
        processIdentifier: Int32
    ) -> String {
        let currentApplicationPath = currentApplicationURL.path.shellQuoted
        let newApplicationPath = newApplicationURL.path.shellQuoted
        let workingDirectoryPath = workingDirectoryURL.path.shellQuoted
        let backupPath = "\(currentApplicationURL.path).previous-update".shellQuoted

        return """
        #!/bin/zsh
        set -euo pipefail

        CURRENT_APP=\(currentApplicationPath)
        NEW_APP=\(newApplicationPath)
        WORK_DIR=\(workingDirectoryPath)
        BACKUP_APP=\(backupPath)
        APP_PID=\(processIdentifier)

        restore_previous_app() {
            if [ -d "$BACKUP_APP" ] && [ ! -d "$CURRENT_APP" ]; then
                /bin/mv "$BACKUP_APP" "$CURRENT_APP"
            fi
        }

        cleanup_and_open() {
            /bin/rm -rf "$BACKUP_APP"
            launch_current_app
            /bin/rm -rf "$WORK_DIR"
        }

        launch_current_app() {
            local console_user
            local console_uid
            console_user=$(/usr/bin/stat -f "%Su" /dev/console 2>/dev/null || true)

            if [ "$(/usr/bin/id -u)" = "0" ] && [ -n "$console_user" ] && [ "$console_user" != "root" ]; then
                console_uid=$(/usr/bin/id -u "$console_user" 2>/dev/null || true)
                if [ -n "$console_uid" ]; then
                    /bin/launchctl asuser "$console_uid" /usr/bin/open "$CURRENT_APP" && return
                fi
            fi

            /usr/bin/open "$CURRENT_APP"
        }

        trap 'restore_previous_app' ERR

        for _ in {1..200}; do
            if ! /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
                break
            fi
            /bin/sleep 0.2
        done

        if /bin/kill -0 "$APP_PID" >/dev/null 2>&1; then
            exit 2
        fi

        /bin/rm -rf "$BACKUP_APP"
        if [ -d "$CURRENT_APP" ]; then
            /bin/mv "$CURRENT_APP" "$BACKUP_APP"
        fi

        /usr/bin/ditto "$NEW_APP" "$CURRENT_APP"
        cleanup_and_open
        """
    }
}

private extension String {
    nonisolated var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
