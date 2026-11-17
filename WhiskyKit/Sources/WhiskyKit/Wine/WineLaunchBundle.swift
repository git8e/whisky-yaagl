//
//  WineLaunchBundle.swift
//  WhiskyKit
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

import Darwin
import Foundation
import os.log

/// A small, generated app bundle that acts as a launch beacon.
///
/// Wine processes usually start as background processes and only get a Dock
/// tile when their first window appears. A launch beacon is opened through
/// LaunchServices just before Wine starts, so macOS creates a normal Dock tile
/// immediately, with the program's name and icon. The beacon requests
/// attention, waits for the first visible Wine window, and then quits. The
/// actual Wine process is left alone and creates its own application tile as
/// usual when the game window appears.
public struct WineLaunchBundle {
    public let bundleURL: URL

    private static let logger = Logger.wineKit
    private static let helperName = "WhiskyCmd"
    private static let launcherName = "launcher"
    private static let bundlePrefix = "com.github.git8e.whisky-yaagl.launch."
    private static let watchTimeout = 45

    /// Generate the beacon and open it through LaunchServices.
    ///
    /// Returns without waiting for the beacon to finish starting. Launching the
    /// Windows program should happen immediately afterwards so the beacon is
    /// already waiting for the first window.
    public static func launch(for programURL: URL, displayName: String? = nil) {
        guard let bundle = prepare(for: programURL, displayName: displayName) else { return }

        // Capture the windows that exist before the game starts. The beacon
        // uses this to distinguish the game window from windows that were
        // already on screen.
        let baseline = WineWindowSnapshot.capture(includeNonWine: true)
        let baselineArgument = baseline.windowIDs.map(String.init).joined(separator: ",")

        // Do this in a separate process rather than through AppKit so the
        // actual game launch path is never blocked by the UI process. `-g`
        // keeps the beacon from taking focus; it still gets a Dock tile and
        // requests attention itself.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-g",
            "-n",
            bundle.bundleURL.path(percentEncoded: false),
            "--args",
            "bounce-watch",
            String(watchTimeout),
            baselineArgument
        ]
        do {
            try process.run()
        } catch {
            logger.error("Failed to open launch beacon: \(error)")
        }
    }

    /// Build (or refresh) the beacon app bundle for `programURL`.
    ///
    /// Returns `nil` when the helper binary is not present (for example when
    /// running a development build directly from Xcode). Callers should then
    /// fall back to launching Wine without a beacon.
    public static func prepare(for programURL: URL, displayName: String? = nil) -> WineLaunchBundle? {
        let fileManager = FileManager.default
        guard let helperURL = helperBinaryURL(),
              fileManager.isExecutableFile(atPath: helperURL.path(percentEncoded: false)) else {
            return nil
        }

        let name = sanitizedDisplayName(
            displayName ?? programURL.deletingPathExtension().lastPathComponent
        )
        let key = stableKey(for: programURL)
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        // Include the app build in the bundle path so LaunchServices does not
        // keep a cached name or a missing icon from an older build.
        let bundleURL = WhiskyPaths.applicationSupportRoot
            .appending(path: "LaunchServices", directoryHint: .isDirectory)
            .appending(path: "\(key)-\(version).app", directoryHint: .isDirectory)
        let contentsURL = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let macOSURL = contentsURL.appending(path: "MacOS", directoryHint: .isDirectory)
        let resourcesURL = contentsURL.appending(path: "Resources", directoryHint: .isDirectory)
        let launcherURL = macOSURL.appending(path: launcherName)

        do {
            try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: launcherURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: launcherURL)
            }
            try fileManager.copyItem(at: helperURL, to: launcherURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: launcherURL.path(percentEncoded: false)
            )
            // A quarantined app copied from a downloaded DMG would otherwise
            // make LaunchServices hesitate before opening the generated bundle.
            launcherURL.path(percentEncoded: false).withCString { path in
                _ = removexattr(path, "com.apple.quarantine", 0)
            }

            let iconName = copyApplicationIcon(to: resourcesURL, fileManager: fileManager)
            var info: [String: Any] = [
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": name,
                "CFBundleExecutable": launcherName,
                "CFBundleIdentifier": bundlePrefix + key,
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": name,
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0",
                "CFBundleSupportedPlatforms": ["MacOSX"],
                "CFBundleVersion": "1",
                "LSApplicationCategoryType": "public.app-category.games",
                "LSMinimumSystemVersion": "14.0",
                "NSHighResolutionCapable": true
            ]
            if let iconName {
                info["CFBundleIconFile"] = iconName
            }
            let data = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try data.write(to: contentsURL.appending(path: "Info.plist"), options: .atomic)

            return WineLaunchBundle(bundleURL: bundleURL)
        } catch {
            logger.error("Failed to prepare launch beacon for `\(name)`: \(error)")
            return nil
        }
    }

    private static func helperBinaryURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL.appending(path: "Contents/Resources/\(helperName)"),
            Bundle.main.resourceURL?.appending(path: helperName)
        ].compactMap { $0 }
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false))
        }
    }

    private static func copyApplicationIcon(to resourcesURL: URL, fileManager: FileManager) -> String? {
        let candidates = [
            Bundle.main.bundleURL.appending(path: "Contents/Resources/AppIcon.icns"),
            Bundle.main.resourceURL?.appending(path: "AppIcon.icns")
        ].compactMap { $0 }
        guard let source = candidates.first(where: {
            fileManager.fileExists(atPath: $0.path(percentEncoded: false))
        }) else {
            logger.debug("No application icon available for launch beacon")
            return nil
        }

        let destination = resourcesURL.appending(path: "AppIcon.icns")
        do {
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            return "AppIcon"
        } catch {
            logger.debug("Could not copy launch beacon icon: \(error)")
            return nil
        }
    }

    private static func sanitizedDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Whisky" : trimmed
        // Bundle display names are shown in the Dock and menu bar. Keep them
        // on one line even if an executable has unusual characters.
        return name.replacingOccurrences(of: "\n", with: " ")
    }

    private static func stableKey(for url: URL) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in url.standardizedFileURL.path(percentEncoded: false).utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
