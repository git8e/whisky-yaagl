//
//  SteamPatch.swift
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

public enum SteamPatch {
    private static var fm: FileManager { FileManager.default }

    private static func system32(prefixURL: URL) -> URL {
        prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
    }

    private static func syswow64(prefixURL: URL) -> URL {
        prefixURL.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
    }

    public static func isInstalled(prefixURL: URL) -> Bool {
        let s32 = system32(prefixURL: prefixURL)
        let sw64 = syswow64(prefixURL: prefixURL)
        let required = [
            s32.appendingPathComponent("steam.exe"),
            sw64.appendingPathComponent("steam.exe"),
            s32.appendingPathComponent("lsteamclient.dll"),
            sw64.appendingPathComponent("lsteamclient.dll")
        ]
        return required.allSatisfy { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    private static func applyCopy(prefixURL: URL) throws {
        if isInstalled(prefixURL: prefixURL) {
            return
        }

        let extras = try HK4eAssets.protonExtrasDir()
        let s32 = system32(prefixURL: prefixURL)
        let sw64 = syswow64(prefixURL: prefixURL)

        try copyReplacing(from: extras.appendingPathComponent("steam64.exe"), to: s32.appendingPathComponent("steam.exe"))
        try copyReplacing(from: extras.appendingPathComponent("steam32.exe"), to: sw64.appendingPathComponent("steam.exe"))
        try copyReplacing(
            from: extras.appendingPathComponent("lsteamclient64.dll"),
            to: s32.appendingPathComponent("lsteamclient.dll")
        )
        try copyReplacing(
            from: extras.appendingPathComponent("lsteamclient32.dll"),
            to: sw64.appendingPathComponent("lsteamclient.dll")
        )
    }

    public static func apply(
        prefixURL: URL,
        status: (@Sendable (String) -> Void)? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if !HK4eProtonExtras.isInstalled() {
            try await HK4eProtonExtras.ensureInstalled(status: status, progress: progress)
        }
        try applyCopy(prefixURL: prefixURL)
    }

    public static func remove(prefixURL: URL) throws {
        let s32 = system32(prefixURL: prefixURL)
        let sw64 = syswow64(prefixURL: prefixURL)
        let targets = [
            s32.appendingPathComponent("steam.exe"),
            sw64.appendingPathComponent("steam.exe"),
            s32.appendingPathComponent("lsteamclient.dll"),
            sw64.appendingPathComponent("lsteamclient.dll")
        ]
        for target in targets {
            if fm.fileExists(atPath: target.path(percentEncoded: false)) {
                try? fm.removeItem(at: target)
            }
        }
    }

    private static func copyReplacing(from src: URL, to dst: URL) throws {
        try FileCopy.copyItem(at: src, to: dst, replacing: true)
    }
}
