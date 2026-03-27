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
    private static var fm: FileManager { FileManager.default }

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

    public static func apply(
        bottle: Bottle,
        width: Int,
        height: Int,
        executableName: String? = nil
    ) async throws {
        guard width > 0, height > 0 else {
            throw HK4eResolutionError.invalidSize(width: width, height: height)
        }

        let keys = applyKeys(executableName: executableName)

        // Use `reg add` so the key is created if missing.
        // Best-effort across candidate keys (some Wine builds may fail on certain Unicode keys).
        var didSucceed = false
        var lastError: String?

        for key in keys {
            do {
                try await runRegAddDword(bottle: bottle, key: key, name: "Screenmanager Is Fullscreen mode_h3981298716", value: 0)
                try await runRegAddDword(bottle: bottle, key: key, name: "Screenmanager Resolution Width_h182942802", value: width)
                try await runRegAddDword(bottle: bottle, key: key, name: "Screenmanager Resolution Height_h2627697771", value: height)
                didSucceed = true
            } catch {
                lastError = error.localizedDescription
            }
        }

        if !didSucceed {
            throw HK4eResolutionError.registryWriteFailed(message: lastError ?? "Failed to write resolution registry keys")
        }
    }

    public static func revert(bottle: Bottle) async throws {
        let keys = revertKeys()

        for key in keys {
            _ = try? await Wine.runWine(["reg", "delete", key, "-v", "Screenmanager Is Fullscreen mode_h3981298716", "-f"], bottle: bottle)
            _ = try? await Wine.runWine(["reg", "delete", key, "-v", "Screenmanager Resolution Width_h182942802", "-f"], bottle: bottle)
            _ = try? await Wine.runWine(["reg", "delete", key, "-v", "Screenmanager Resolution Height_h2627697771", "-f"], bottle: bottle)
        }
    }

    private static func runRegAddDword(bottle: Bottle, key: String, name: String, value: Int) async throws {
        let output = try await Wine.runWine(
            ["reg", "add", key, "-v", name, "-t", "REG_DWORD", "-d", String(value), "-f"],
            bottle: bottle,
            environment: ["WINEDEBUG": "-all"]
        )

        // Wine prefix init can emit unrelated errors (hostname, winemenubuilder).
        // Only fail on registry-specific errors and keep the message short.
        if output.contains("reg: Unable to") || output.contains("Unable to access or create") {
            let msg = output
                .split(whereSeparator: { $0.isNewline })
                .last
                .map(String.init)
                ?? output
            throw HK4eResolutionError.registryWriteFailed(message: msg)
        }
    }

    private static func applyKeys(executableName: String?) -> [String] {
        let base = #"HKEY_CURRENT_USER\Software\miHoYo\"#

        if let executableName {
            let lower = executableName.lowercased()
            if lower.contains("yuanshen") {
                return [base + "原神"]
            }
            if lower.contains("genshinimpact") {
                return [base + "Genshin Impact"]
            }
        }

        return [base + "Genshin Impact"]
    }

    private static func revertKeys() -> [String] {
        let base = #"HKEY_CURRENT_USER\Software\miHoYo\"#
        return [
            base + "Genshin Impact",
            base + "原神"
        ]
    }
}

public enum HK4eResolutionError: LocalizedError {
    case invalidSize(width: Int, height: Int)
    case registryWriteFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSize(let width, let height):
            return "Invalid resolution: \(width)x\(height)"
        case .registryWriteFailed(let message):
            return message
        }
    }
}
