//
//  SparkleView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import AppKit
import SwiftUI
import WhiskyKit

struct SparkleView: View {
    @State private var isCheckingForUpdates = false

    var body: some View {
        Button("check.updates") {
            isCheckingForUpdates = true
            Task {
                await AppUpdateChecker.shared.checkForUpdates(userInitiated: true)
                await MainActor.run {
                    isCheckingForUpdates = false
                }
            }
        }
        .disabled(isCheckingForUpdates)
    }
}

@MainActor
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()

    private let releasesAPIURL = URL(string: "https://api.github.com/repos/git8e/whisky-yaagl/releases/latest")!
    private let fallbackReleasesURL = URL(string: "https://github.com/git8e/whisky-yaagl/releases/latest")!
    private let lastCheckKey = "lastAppUpdateCheck"
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private init() {}

    func checkForUpdatesIfNeeded() async {
        let defaults = UserDefaults.standard
        let automaticChecksEnabled = defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        guard automaticChecksEnabled else { return }

        if let lastCheck = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < automaticCheckInterval {
            return
        }

        await checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) async {
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        do {
            let release = try await fetchLatestRelease()
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let latestVersion = normalizedVersion(release.tagName)

            if isVersion(latestVersion, newerThan: currentVersion) {
                let alert = NSAlert()
                alert.messageText = String(localized: "updates.available.title")
                alert.informativeText = String(
                    format: String(localized: "updates.available.message"),
                    latestVersion,
                    currentVersion
                )
                alert.addButton(withTitle: String(localized: "button.openReleases"))
                alert.addButton(withTitle: String(localized: "button.ok"))

                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(release.url)
                }
            } else if userInitiated {
                let alert = NSAlert()
                alert.messageText = String(localized: "updates.latest.title")
                alert.informativeText = String(localized: "updates.latest.message")
                alert.addButton(withTitle: String(localized: "button.ok"))
                alert.runModal()
            }
        } catch {
            if userInitiated {
                let alert = NSAlert()
                alert.messageText = String(localized: "updates.failed.title")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: String(localized: "button.openReleases"))
                alert.addButton(withTitle: String(localized: "button.ok"))

                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(fallbackReleasesURL)
                }
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("whisky-yaagl", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        return GitHubRelease(
            tagName: release.tagName,
            url: URL(string: release.htmlURL) ?? fallbackReleasesURL
        )
    }

    private func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let core = withoutPrefix.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? withoutPrefix
        return core.isEmpty ? withoutPrefix : core
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsComponents = versionComponents(lhs)
        let rhsComponents = versionComponents(rhs)
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0
            if lhsValue != rhsValue {
                return lhsValue > rhsValue
            }
        }

        return false
    }

    private func versionComponents(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }

        init(tagName: String, url: URL) {
            self.tagName = tagName
            htmlURL = url.absoluteString
        }

        var url: URL {
            URL(string: htmlURL) ?? URL(string: "https://github.com/git8e/whisky-yaagl/releases/latest")!
        }
    }
}

@MainActor
final class WineUpdateChecker {
    static let shared = WineUpdateChecker()

    private let lastCheckKey = "lastWineUpdateCheck"
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private let settingsKey = "checkWineRuntimeUpdates"

    private init() {}

    func checkForUpdatesIfNeeded(openSetup: @escaping @MainActor () -> Void) async {
        let defaults = UserDefaults.standard
        let automaticChecksEnabled = defaults.object(forKey: settingsKey) as? Bool ?? false
        guard automaticChecksEnabled else { return }

        if let lastCheck = defaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < automaticCheckInterval {
            return
        }

        defaults.set(Date(), forKey: lastCheckKey)

        let updates = await WineRuntimes.availableInstalledUpdates()
        guard !updates.isEmpty else { return }

        let lines = updates.map { update in
            "- \(update.installed.displayName) -> \(update.latest.displayName)"
        }.joined(separator: "\n")

        let alert = NSAlert()
        alert.messageText = String(localized: "wineUpdates.available.title")
        alert.informativeText = String(
            format: String(localized: "wineUpdates.available.message"),
            lines
        )
        alert.addButton(withTitle: String(localized: "button.openSetup"))
        alert.addButton(withTitle: String(localized: "button.ok"))

        if alert.runModal() == .alertFirstButtonReturn {
            openSetup()
        }
    }
}
