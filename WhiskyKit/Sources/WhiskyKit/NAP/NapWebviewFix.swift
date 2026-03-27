//
//  NapWebviewFix.swift
//  WhiskyKit
//

import Foundation

public enum NapWebviewFix {
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

    public static func applyIfNeeded(bottle: Bottle, region: NapGame.Region) async {
        let key = NapGame.registryKey(region: region)

        var deleteNames: [String] = ["MIHOYOSDK_WEBVIEW_RENDER_METHOD_h1573598267"]
        do {
            let output = try await Wine.runWine(
                ["reg", "query", key],
                bottle: bottle,
                environment: [
                    "WINEDEBUG": "-all",
                    "WINEESYNC": "0",
                    "WINEMSYNC": "0"
                ],
                log: false
            )

            for rawLine in output.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("HOYO_WEBVIEW_RENDER_METHOD_ABTEST_") else { continue }
                // reg query output is typically: NAME    TYPE    DATA
                if let name = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first {
                    deleteNames.append(String(name))
                }
            }
        } catch {
            // Key might not exist; still attempt the base deletion.
        }

        deleteNames = Array(Set(deleteNames))
        let lines: [String] =
            [
                "Windows Registry Editor Version 5.00",
                "",
                "[\(key)]"
            ]
            + deleteNames.map { name in
                "\"\(name)\"=-"
            }

        do {
            let dir = try workDir(bottle: bottle)
            let regURL = dir.appendingPathComponent("nap_fix_webview.reg", isDirectory: false)
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
