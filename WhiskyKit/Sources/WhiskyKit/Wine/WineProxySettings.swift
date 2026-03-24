import Foundation

public enum WineProxySettings {
    private static var fm: FileManager { FileManager.default }

    private struct DesiredState: Codable, Equatable {
        var enabled: Bool
        var server: String
    }

    private static func workDir(bottle: Bottle) throws -> URL {
        let dir = bottle.url.appendingPathComponent("Wine", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func stateURL(bottle: Bottle) throws -> URL {
        try workDir(bottle: bottle).appending(path: "proxy-config.json")
    }

    private static func regURL(bottle: Bottle) throws -> URL {
        try workDir(bottle: bottle).appending(path: "proxy-config.reg")
    }

    private static func toWinePath(_ absPath: String) -> String {
        "Z:" + absPath.replacingOccurrences(of: "/", with: "\\")
    }

    private static func writeUTF16LEFile(url: URL, text: String) throws {
        var data = Data()
        data.append(0xff)
        data.append(0xfe)
        data.append(contentsOf: text.utf16.flatMap { value -> [UInt8] in
            let code = UInt16(value)
            return [UInt8(code & 0xff), UInt8((code >> 8) & 0xff)]
        })
        try data.write(to: url)
    }

    private static func desiredState(bottle: Bottle) -> DesiredState {
        DesiredState(enabled: bottle.settings.proxyEnabled, server: bottle.settings.proxyServer.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func loadState(bottle: Bottle) -> DesiredState? {
        do {
            let url = try stateURL(bottle: bottle)
            guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            return try JSONDecoder().decode(DesiredState.self, from: Data(contentsOf: url))
        } catch {
            return nil
        }
    }

    private static func saveState(bottle: Bottle, state: DesiredState) {
        do {
            let url = try stateURL(bottle: bottle)
            try JSONEncoder().encode(state).write(to: url)
        } catch {
            // ignore
        }
    }

    private static func buildRegistryContent(state: DesiredState) -> String {
        var lines = [
            "Windows Registry Editor Version 5.00",
            "",
            #"[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings]"#,
            String(format: #""ProxyEnable"=dword:%08x"#, state.enabled ? 1 : 0)
        ]

        if state.enabled, !state.server.isEmpty {
            let escaped = state.server.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: #"\""#)
            lines.append("\"ProxyServer\"=\"\(escaped)\"")
        } else {
            lines.append(#""ProxyServer"=-"#)
        }

        return lines.joined(separator: "\r\n")
    }

    public static func applyIfNeeded(bottle: Bottle) async throws {
        let state = desiredState(bottle: bottle)
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
                "WINEESYNC": "0",
                "WINEMSYNC": "0"
            ]
        )
        saveState(bottle: bottle, state: state)
    }
}
