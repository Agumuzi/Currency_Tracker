//
//  SoftwareUpdateChecker.swift
//  Currency Tracker
//
//  Created by Codex on 4/24/26.
//

import Foundation

nonisolated struct SoftwareUpdateInfo: Equatable, Sendable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL?
    let checksumURL: URL?
    let title: String?
    let releaseNotes: String?

    func isNewer(than currentVersion: String) -> Bool {
        SoftwareVersionComparator.compare(version, currentVersion) == .orderedDescending
    }
}

nonisolated enum SoftwareUpdateChecker {
    static let releasesURL = URL(string: "https://github.com/Agumuzi/Currency_Tracker/releases")!
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/Agumuzi/Currency_Tracker/releases/latest")!

    static func currentVersion(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func fetchLatestRelease(
        session: URLSession = .shared,
        apiURL: URL = latestReleaseAPIURL
    ) async throws -> SoftwareUpdateInfo {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Currency Tracker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode) == false {
            throw SoftwareUpdateError.invalidResponse
        }

        return try parseLatestRelease(from: data)
    }

    static func parseLatestRelease(from data: Data) throws -> SoftwareUpdateInfo {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let releaseURL = URL(string: release.htmlURL) else {
            throw SoftwareUpdateError.invalidReleaseURL
        }

        let zipAsset = release.assets.first { asset in
            asset.name.hasSuffix(".zip") && asset.name.contains("Currency-Tracker")
        }
        let downloadURL = zipAsset.flatMap { URL(string: $0.browserDownloadURL) }
        let checksumURL = zipAsset
            .flatMap { checksumAsset(for: $0, assets: release.assets) }
            .flatMap { URL(string: $0.browserDownloadURL) }

        return SoftwareUpdateInfo(
            version: SoftwareVersionComparator.normalized(release.tagName),
            releaseURL: releaseURL,
            downloadURL: downloadURL,
            checksumURL: checksumURL,
            title: trimmedNonEmpty(release.name),
            releaseNotes: trimmedNonEmpty(release.body)
        )
    }

    private static func checksumAsset(
        for zipAsset: GitHubReleaseAsset,
        assets: [GitHubReleaseAsset]
    ) -> GitHubReleaseAsset? {
        let expectedNames = [
            "\(zipAsset.name).sha256",
            zipAsset.name.replacingOccurrences(of: ".zip", with: ".sha256")
        ]

        return assets.first { asset in
            expectedNames.contains(asset.name)
        } ?? assets.first { asset in
            asset.name.hasSuffix(".sha256") && asset.name.contains("Currency-Tracker")
        }
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum SoftwareUpdateError: Error {
    case invalidResponse
    case invalidReleaseURL
}

nonisolated enum SoftwareVersionComparator {
    static func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }

        return trimmed
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = numericParts(from: normalized(lhs))
        let rhsParts = numericParts(from: normalized(rhs))
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0

            if left > right {
                return .orderedDescending
            }

            if left < right {
                return .orderedAscending
            }
        }

        return .orderedSame
    }

    private static func numericParts(from version: String) -> [Int] {
        version.split(separator: ".").map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }
}

nonisolated private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

nonisolated private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
