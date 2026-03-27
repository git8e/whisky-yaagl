//
//  HK4eHDR.swift
//  WhiskyKit
//

import Foundation

public enum HK4eHDR {
    private static var fm: FileManager { FileManager.default }

    private static let hdrOSURL = URL(
        string: "https://raw.githubusercontent.com/yaagl/yet-another-anime-game-launcher/main/src/constants/hk4e_hdr_os.reg"
    )!
    private static let hdrCNURL = URL(
        string: "https://raw.githubusercontent.com/yaagl/yet-another-anime-game-launcher/main/src/constants/hk4e_hdr_cn.reg"
    )!

    private static func toWinePath(_ absPath: String) -> String {
        return "Z:" + absPath.replacingOccurrences(of: "/", with: "\\")
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

    private static func hk4eWorkDir(bottle: Bottle) throws -> URL {
        let dir = bottle.url.appendingPathComponent("HK4e", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func apply(bottle: Bottle, region: HK4eGame.Region) async throws {
        let url = (region == .cn) ? hdrCNURL : hdrOSURL

        let (data, _) = try await URLSession(configuration: .ephemeral).data(from: url)
        let content = String(data: data, encoding: .utf8) ?? ""

        let dir = try hk4eWorkDir(bottle: bottle)
        let regURL = dir.appendingPathComponent("hk4e_enable_hdr.reg")
        try writeUTF16LEFile(url: regURL, text: content.replacingOccurrences(of: "\n", with: "\r\n"))
        defer { try? fm.removeItem(at: regURL) }

        let regWinePath = toWinePath(regURL.path(percentEncoded: false))
        _ = try await Wine.runWine(["regedit", regWinePath], bottle: bottle, environment: ["WINEDEBUG": "-all"])
    }

    public static func apply(bottle: Bottle, executableName: String?) async throws {
        let region = HK4eGame.resolveRegion(executableName: executableName ?? "", fallback: .os)
        try await apply(bottle: bottle, region: region)
    }

    public static func revert(bottle: Bottle, region: HK4eGame.Region) async {
        let key = (region == .cn) ? #"HKEY_CURRENT_USER\Software\miHoYo\原神"# : #"HKEY_CURRENT_USER\Software\miHoYo\Genshin Impact"#

        let lines: [String] = [
            "Windows Registry Editor Version 5.00",
            "",
            "[\(key)]",
            #""WINDOWS_HDR_ON_h3132281285"=-"#
        ]

        do {
            let dir = try hk4eWorkDir(bottle: bottle)
            let regURL = dir.appendingPathComponent("hk4e_revert_hdr.reg")
            try writeUTF16LEFile(url: regURL, text: lines.joined(separator: "\r\n"))
            defer { try? fm.removeItem(at: regURL) }

            let regWinePath = toWinePath(regURL.path(percentEncoded: false))
            _ = try await Wine.runWine(["regedit", regWinePath], bottle: bottle, environment: ["WINEDEBUG": "-all"])
        } catch {
            // ignore
        }
    }

    public static func revert(bottle: Bottle, executableName: String?) async {
        let region = HK4eGame.resolveRegion(executableName: executableName ?? "", fallback: .os)
        await revert(bottle: bottle, region: region)
    }
}
