//
//  NapResolution.swift
//  WhiskyKit
//

import Foundation

public enum NapResolution {
    private static var fm: FileManager { FileManager.default }

    private static func workDir(bottle: Bottle) throws -> URL {
        let dir = bottle.url.appendingPathComponent("NAP", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func toWinePath(_ absPath: String) -> String {
        "Z:" + absPath.replacingOccurrences(of: "/", with: "\\")
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

    public static func revertIfNeeded(bottle: Bottle, region: NapGame.Region) async {
        let key = NapGame.registryKey(region: region)
        let lines = [
            "Windows Registry Editor Version 5.00",
            "",
            "[\(key)]",
            #"\"Screenmanager Is Fullscreen mode_h3981298716\"=-"#,
            #"\"Screenmanager Resolution Width_h182942802\"=-"#,
            #"\"Screenmanager Resolution Height_h2627697771\"=-"#
        ]

        do {
            let dir = try workDir(bottle: bottle)
            let regURL = dir.appendingPathComponent("nap_revert_resolution.reg", isDirectory: false)
            try writeUTF16LEFile(url: regURL, text: lines.joined(separator: "\r\n"))
            defer { try? fm.removeItem(at: regURL) }

            let regWinePath = toWinePath(regURL.path(percentEncoded: false))
            _ = try await Wine.runWine(
                ["regedit", regWinePath],
                bottle: bottle,
                environment: [
                    "WINEDEBUG": "-all",
                    "WINEESYNC": "0",
                    "WINEMSYNC": "0"
                ]
            )
        } catch {
            // best-effort
        }
    }
}
