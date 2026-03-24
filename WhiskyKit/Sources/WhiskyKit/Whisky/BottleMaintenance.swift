//
//  BottleMaintenance.swift
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

import Foundation

public enum BottleMaintenance {
    private static var fm: FileManager { FileManager.default }

    public static func cleanHK4eTweaks(bottle: Bottle) async {
        await HK4ePatch.revertIfNeeded(bottle: bottle, prefixURL: bottle.url)

        do {
            for await _ in try Wine.runWineserverProcess(args: ["-k"], bottle: bottle) { }
        } catch {
            // best-effort
        }

        do {
            try SteamPatch.remove(prefixURL: bottle.url)
        } catch {
            // best-effort
        }

        do {
            try await HK4eResolution.revert(bottle: bottle)
        } catch {
            // best-effort
        }

        await HK4eHDR.revert(bottle: bottle, executableName: bottle.settings.hk4eGameExecutableURL?.lastPathComponent)

        if bottle.settings.hk4eEnableNVExtension == false {
            await HK4eTweaks.revertNVExtension(bottle: bottle)
        }

        do {
            for await _ in try Wine.runWineserverProcess(args: ["-w"], bottle: bottle) { }
        } catch {
            // best-effort
        }
    }

    public static func resetPrefix(bottle: Bottle) async throws {
        // Capture a few settings that live in registry only.
        let preserveRetina: Bool = (try? await Wine.retinaMode(bottle: bottle)) ?? false

        do {
            for await _ in try Wine.runWineserverProcess(args: ["-k"], bottle: bottle) { }
        } catch {
            // best-effort
        }

        try removePrefixContentsKeepingMetadata(prefixURL: bottle.url)

        _ = try await Wine.runWine(["wineboot", "-u"], bottle: bottle)
        _ = try await Wine.changeWinVersion(bottle: bottle, win: bottle.settings.windowsVersion)

        if preserveRetina {
            try await Wine.changeRetinaMode(bottle: bottle, retinaMode: true)
        }

        if bottle.settings.hk4eSteamPatch {
            try await SteamPatch.apply(prefixURL: bottle.url)
        }

        // Custom resolution and HDR are applied per-launch.

        do {
            for await _ in try Wine.runWineserverProcess(args: ["-w"], bottle: bottle) { }
        } catch {
            // best-effort
        }
    }

    private static func removePrefixContentsKeepingMetadata(prefixURL: URL) throws {
        let keepNames: Set<String> = [
            "Metadata.plist",
            "Program Settings"
        ]

        let entries = try fm.contentsOfDirectory(at: prefixURL, includingPropertiesForKeys: nil)
        for entry in entries {
            if keepNames.contains(entry.lastPathComponent) {
                continue
            }
            try? fm.removeItem(at: entry)
        }
    }
}
