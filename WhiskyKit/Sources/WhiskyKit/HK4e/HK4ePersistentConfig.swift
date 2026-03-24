//
//  HK4ePersistentConfig.swift
//  WhiskyKit
//

import Foundation

public enum HK4ePersistentConfig {
    private static var fm: FileManager { FileManager.default }

    private struct DesiredState: Codable, Equatable {
        var leftCommandIsCtrl: Bool
        var customResolutionEnabled: Bool
        var customResolutionWidth: Int
        var customResolutionHeight: Int
    }

    private static func hk4eWorkDir(bottle: Bottle) throws -> URL {
        let dir = bottle.url.appendingPathComponent("HK4e", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func stateURL(bottle: Bottle) throws -> URL {
        try hk4eWorkDir(bottle: bottle).appending(path: "persistent-config.json")
    }

    private static func regURL(bottle: Bottle) throws -> URL {
        try hk4eWorkDir(bottle: bottle).appending(path: "persistent-config.reg")
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

    private static func desiredState(bottle: Bottle) -> DesiredState {
        DesiredState(
            leftCommandIsCtrl: bottle.settings.hk4eLeftCommandIsCtrl,
            customResolutionEnabled: bottle.settings.hk4eCustomResolutionEnabled,
            customResolutionWidth: bottle.settings.hk4eCustomResolutionWidth,
            customResolutionHeight: bottle.settings.hk4eCustomResolutionHeight
        )
    }

    private static func isDefaultState(_ state: DesiredState) -> Bool {
        state.leftCommandIsCtrl == false && state.customResolutionEnabled == false
    }

    private static func loadState(bottle: Bottle) -> DesiredState? {
        do {
            let url = try stateURL(bottle: bottle)
            guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DesiredState.self, from: data)
        } catch {
            return nil
        }
    }

    private static func saveState(bottle: Bottle, state: DesiredState) {
        do {
            let url = try stateURL(bottle: bottle)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url)
        } catch {
            // ignore
        }
    }

    private static func buildRegistryContent(state: DesiredState) -> String {
        var lines = [
            "Windows Registry Editor Version 5.00",
            "",
            #"[HKEY_CURRENT_USER\Software\Wine\Mac Driver]"#,
            "\"LeftCommandIsCtrl\"=\"\(state.leftCommandIsCtrl ? "y" : "n")\"",
            "",
            #"[HKEY_CURRENT_USER\Software\miHoYo\Genshin Impact]"#
        ]

        if state.customResolutionEnabled, state.customResolutionWidth > 0, state.customResolutionHeight > 0 {
            lines.append(#""Screenmanager Is Fullscreen mode_h3981298716"=dword:00000000"#)
            lines.append(String(format: "\"Screenmanager Resolution Width_h182942802\"=dword:%08x", state.customResolutionWidth))
            lines.append(String(format: "\"Screenmanager Resolution Height_h2627697771\"=dword:%08x", state.customResolutionHeight))
        } else {
            lines.append(#""Screenmanager Is Fullscreen mode_h3981298716"=-"#)
            lines.append(#""Screenmanager Resolution Width_h182942802"=-"#)
            lines.append(#""Screenmanager Resolution Height_h2627697771"=-"#)
        }

        return lines.joined(separator: "\r\n")
    }

    public static func applyIfNeeded(bottle: Bottle) async throws {
        let state = desiredState(bottle: bottle)
        if isDefaultState(state) && loadState(bottle: bottle) == nil {
            return
        }
        if loadState(bottle: bottle) == state {
            return
        }

        let regFileURL = try regURL(bottle: bottle)
        try writeUTF16LEFile(url: regFileURL, text: buildRegistryContent(state: state))
        defer { try? fm.removeItem(at: regFileURL) }

        let regWinePath = toWinePath(regFileURL.path(percentEncoded: false))
        _ = try await Wine.runWine(
            ["regedit", regWinePath],
            bottle: bottle,
            environment: [
                "WINEDEBUG": "-all",
                // Registry import doesn't need sync enhancements.
                "WINEESYNC": "0",
                "WINEMSYNC": "0"
            ]
        )
        saveState(bottle: bottle, state: state)
    }
}
