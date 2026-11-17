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

import AppKit
import Foundation
import os.log

/// A generated `.app` wrapper for a Windows program.
///
/// Wine processes start as background processes. They only get a Dock tile when
/// the first window is created, so the Dock never sees a normal app launch and
/// does not bounce the icon. Wrapping the Wine invocation in a tiny app bundle
/// gives the process a regular Dock tile as soon as it starts. The helper then
/// requests attention and `exec`s Wine, keeping the same process and bundle
/// identity while the game window is loading.
public struct WineLaunchBundle {
    public let executableURL: URL

    private static let logger = Logger.wineKit
    private static let helperName = "WhiskyCmd"
    private static let launcherName = "launcher"
    private static let bundlePrefix = "com.github.git8e.whisky-yaagl.launch."

    /// Build (or refresh) the wrapper for `programURL`.
    ///
    /// Returns `nil` when the helper binary is not present (for example when
    /// running a development build directly from Xcode). Callers should then
    /// fall back to launching Wine directly.
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
        let bundleURL = WhiskyPaths.applicationSupportRoot
            .appending(path: "LaunchServices", directoryHint: .isDirectory)
            .appending(path: "\(key).app", directoryHint: .isDirectory)
        let contentsURL = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let macOSURL = contentsURL.appending(path: "MacOS", directoryHint: .isDirectory)
        let resourcesURL = contentsURL.appending(path: "Resources", directoryHint: .isDirectory)
        let launcherURL = macOSURL.appending(path: launcherName)

        do {
            try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

            // Refresh the helper so an app update cannot leave an old wrapper
            // invocation contract behind.
            if fileManager.fileExists(atPath: launcherURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: launcherURL)
            }
            try fileManager.copyItem(at: helperURL, to: launcherURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: launcherURL.path(percentEncoded: false)
            )

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

            return WineLaunchBundle(executableURL: launcherURL)
        } catch {
            logger.error("Failed to prepare Wine launch bundle for `\(name)`: \(error)")
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
        guard let source = Bundle.main.resourceURL?.appending(path: "AppIcon.icns"),
              fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            return nil
        }

        let destination = resourcesURL.appending(path: "AppIcon.icns")
        if !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                logger.debug("Could not copy launch icon: \(error)")
                return nil
            }
        }
        return "AppIcon"
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
