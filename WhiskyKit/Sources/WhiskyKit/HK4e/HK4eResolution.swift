//
//  HK4eResolution.swift
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

public enum HK4eResolution {
    private static let fm = FileManager.default

    private static func toWinePath(_ absPath: String) -> String {
        return "Z:" + absPath.replacingOccurrences(of: "/", with: "\\")
    }

    private static func hk4eWorkDir(bottle: Bottle) throws -> URL {
        let dir = bottle.url.appendingPathComponent("HK4e", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func writeUTF16LEFile(url: URL, text: String) throws {
        var data = Data()
        data.append(0xff)
        data.append(0xfe)
        data.append(contentsOf: text.utf16.flatMap { u -> [UInt8] in
            let v = UInt16(u)
            return [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]
        })
        try data.write(to: url)
    }

    public static func apply(bottle: Bottle, width: Int, height: Int) async throws {
        guard width > 0, height > 0 else {
            throw HK4eResolutionError.invalidSize(width: width, height: height)
        }

        let keys: [String] = [
            #"HKEY_CURRENT_USER\\Software\\miHoYo\\Genshin Impact"#,
            #"HKEY_CURRENT_USER\\Software\\miHoYo\\原神"#
        ]

        var lines: [String] = [
            "Windows Registry Editor Version 5.00",
            ""
        ]

        for key in keys {
            lines.append("[\(key)]")
            lines.append(#"\"Screenmanager Is Fullscreen mode_h3981298716\"=dword:00000000"#)
            lines.append(String(format: "\"Screenmanager Resolution Width_h182942802\"=dword:%08x", width))
            lines.append(String(format: "\"Screenmanager Resolution Height_h2627697771\"=dword:%08x", height))
            lines.append("")
        }

        let dir = try hk4eWorkDir(bottle: bottle)
        let regURL = dir.appendingPathComponent("hk4e_resolution.reg", isDirectory: false)
        try writeUTF16LEFile(url: regURL, text: lines.joined(separator: "\r\n"))
        defer { try? fm.removeItem(at: regURL) }

        let regWinePath = toWinePath(regURL.path(percentEncoded: false))
        _ = try await Wine.runWine(["regedit", regWinePath], bottle: bottle)
    }

    public static func revert(bottle: Bottle) async throws {
        let keys: [String] = [
            #"HKEY_CURRENT_USER\\Software\\miHoYo\\Genshin Impact"#,
            #"HKEY_CURRENT_USER\\Software\\miHoYo\\原神"#
        ]

        var lines: [String] = [
            "Windows Registry Editor Version 5.00",
            ""
        ]

        for key in keys {
            lines.append("[\(key)]")
            lines.append(#"\"Screenmanager Is Fullscreen mode_h3981298716\"=-"#)
            lines.append(#"\"Screenmanager Resolution Width_h182942802\"=-"#)
            lines.append(#"\"Screenmanager Resolution Height_h2627697771\"=-"#)
            lines.append("")
        }

        let dir = try hk4eWorkDir(bottle: bottle)
        let regURL = dir.appendingPathComponent("hk4e_resolution_revert.reg", isDirectory: false)
        try writeUTF16LEFile(url: regURL, text: lines.joined(separator: "\r\n"))
        defer { try? fm.removeItem(at: regURL) }

        let regWinePath = toWinePath(regURL.path(percentEncoded: false))
        _ = try await Wine.runWine(["regedit", regWinePath], bottle: bottle)
    }
}

public enum HK4eResolutionError: LocalizedError {
    case invalidSize(width: Int, height: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidSize(let width, let height):
            return "Invalid resolution: \(width)x\(height)"
        }
    }
}
