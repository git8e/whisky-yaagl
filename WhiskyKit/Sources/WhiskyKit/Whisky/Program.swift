//
//  Program.swift
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
import SwiftUI
import os.log

// swiftlint:disable:next todo
// TODO: Should not be unchecked!
public final class Program: ObservableObject, Equatable, Hashable, Identifiable, @unchecked Sendable {
    public let bottle: Bottle
    public let url: URL
    public let settingsURL: URL

    public var name: String {
        url.lastPathComponent
    }

    /// Name shown for the program in the UI and in its launch Dock tile.
    /// Prefer the pin's display name when the program has been pinned.
    public var displayName: String {
        bottle.settings.pins.first(where: { pin in
            guard let pinURL = pin.url else { return false }
            return pinURL.isSameFile(as: url)
        })?.name ?? url.deletingPathExtension().lastPathComponent
    }

    /// Name shown for the transient Dock icon while starting.
    ///
    /// Prefer the name displayed by the main window's pin. If the program is
    /// not pinned, use the executable's file name, and let the launch bundle
    /// fall back to `wine` only when no usable name exists.
    public var launchDisplayName: String {
        if let pinnedName = bottle.settings.pins.first(where: { pin in
            guard let pinURL = pin.url else { return false }
            return pinURL.isSameFile(as: url)
        })?.name.trimmingCharacters(in: .whitespacesAndNewlines), !pinnedName.isEmpty {
            return pinnedName
        }

        let executableName = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return executableName.isEmpty ? "wine" : executableName
    }

    /// Icon shown in the main window for this program. This is the same image
    /// the pins and Installed Programs views use.
    public var launchIcon: NSImage? {
        guard let icon = peFile?.bestIcon(),
              icon.size.width > 0,
              icon.size.height > 0 else {
            return nil
        }
        return icon
    }

    @Published public var settings: ProgramSettings {
        didSet { saveSettings() }
    }

    @Published public var pinned: Bool {
        didSet {
            guard pinned != oldValue else { return }
            if pinned {
                guard !bottle.settings.pins.contains(where: { pin in
                    guard let pinURL = pin.url else { return false }
                    return pinURL.isSameFile(as: url)
                }) else { return }
                bottle.settings.pins.append(PinnedProgram(
                    name: name.replacingOccurrences(of: ".exe", with: ""),
                    url: url
                ))
            } else {
                bottle.settings.pins.removeAll(where: { pin in
                    guard let pinURL = pin.url else { return false }
                    return pinURL.isSameFile(as: url)
                })
            }
        }
    }

    @Published public var isLaunching: Bool = false
    @Published public var hasVisibleWindow: Bool = false
    @Published public var lastExitCode: Int? = nil

    /// True only while the app is starting and its window has not appeared yet.
    /// `isLaunching` intentionally stays true for the lifetime of a game so a
    /// second click cannot start another instance.
    public var isStarting: Bool {
        isLaunching && !hasVisibleWindow
    }

    /// Uninstallers are not useful on the bottle home screen; they often have
    /// a missing or white icon and are better reached from Installed Programs.
    public var isUninstaller: Bool {
        Self.isUninstallerExecutable(url)
    }

    public static func isUninstallerExecutable(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return name == "unins000"
            || name == "uninst"
            || name == "uninstall"
            || name.hasPrefix("uninstall")
            || name.hasPrefix("unins")
    }

    public let peFile: PEFile?

    public init(url: URL, bottle: Bottle) {
        let name = url.lastPathComponent
        self.bottle = bottle
        self.url = url
        self.pinned = bottle.settings.pins.contains(where: { pin in
            guard let pinURL = pin.url else { return false }
            return pinURL.isSameFile(as: url)
        })

        // Warning: This will break if two programs share the same name such as "Launch.exe"
        // Best to add some sort of UUID in the path or file
        let settingsFolder = bottle.url.appending(path: "Program Settings")
        let settingsUrl = settingsFolder.appending(path: name).appendingPathExtension("plist")
        self.settingsURL = settingsUrl

        do {
            if !FileManager.default.fileExists(atPath: settingsFolder.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: settingsFolder, withIntermediateDirectories: true)
            }

            self.settings = try ProgramSettings.decode(from: settingsUrl)
        } catch {
            Logger.wineKit.error("Failed to load settings for `\(name)`: \(error)")
            self.settings = ProgramSettings()
        }

        do {
            self.peFile = try PEFile(url: url)
        } catch {
            self.peFile = nil
        }
    }

    public func generateEnvironment() -> [String: String] {
        var environment = settings.environment
        if settings.locale != .auto {
            environment["LC_ALL"] = settings.locale.rawValue
        }
        return environment
    }

    /// Save the settings to file
    private func saveSettings() {
        do {
            try settings.encode(to: settingsURL)
        } catch {
            Logger.wineKit.error("Failed to save settings for `\(self.name)`: \(error)")
        }
    }

    // MARK: - Equatable

    public static func == (lhs: Program, rhs: Program) -> Bool {
        return lhs.url == rhs.url
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        return hasher.combine(url)
    }

    // MARK: - Identifiable

    public var id: URL {
        self.url
    }
}
