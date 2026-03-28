import Foundation

public enum WineProxySettings {
    private static var fm: FileManager { FileManager.default }

    private struct DesiredState: Codable, Equatable {
        var enabled: Bool
        var host: String
        var port: String
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
        let host = bottle.settings.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = bottle.settings.proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = port.isEmpty ? host : "\(host):\(port)"
        // Avoid a Wine wininet crash when ProxyEnable=1 but ProxyServer is missing/empty.
        let enabled = bottle.settings.proxyEnabled && !server.isEmpty
        return DesiredState(enabled: enabled, host: host, port: port)
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
        let server = state.port.isEmpty ? state.host : "\(state.host):\(state.port)"
        let enabled = state.enabled && !server.isEmpty
        var lines = [
            "Windows Registry Editor Version 5.00",
            "",
            #"[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings]"#,
            String(format: #""ProxyEnable"=dword:%08x"#, enabled ? 1 : 0)
        ]

        if enabled {
            let escaped = server.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: #"\""#)
            lines.append("\"ProxyServer\"=\"\(escaped)\"")
        } else {
            lines.append(#""ProxyServer"=-"#)
        }

        return lines.joined(separator: "\r\n")
    }

    private static func apply(state: DesiredState, bottle: Bottle, persistState: Bool) async throws {
        let regFileURL = try regURL(bottle: bottle)
        try writeUTF16LEFile(url: regFileURL, text: buildRegistryContent(state: state))
        defer { try? fm.removeItem(at: regFileURL) }

        let regWinePath = toWinePath(regFileURL.path(percentEncoded: false))
        do {
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
            // If Wine can't boot (e.g. wininet crash), fall back to offline registry patching.
            try applyOffline(bottle: bottle, state: state)
        }

        if persistState {
            saveState(bottle: bottle, state: state)
        }
    }

    public static func applyIfNeeded(bottle: Bottle) async throws {
        let state = desiredState(bottle: bottle)
        if loadState(bottle: bottle) == state {
            return
        }

        try await apply(state: state, bottle: bottle, persistState: true)
    }

    // MARK: - Temporary overrides (YAAGL-style launch fix)

    public static func applyTemporaryOverride(
        bottle: Bottle,
        enabled: Bool,
        host: String,
        port: String
    ) async throws {
        let state = DesiredState(enabled: enabled, host: host, port: port)
        try await apply(state: state, bottle: bottle, persistState: false)
    }

    public static func restoreDesiredState(bottle: Bottle) async throws {
        let state = desiredState(bottle: bottle)
        try await apply(state: state, bottle: bottle, persistState: true)
    }

    private static func applyOffline(bottle: Bottle, state: DesiredState) throws {
        let regURL = bottle.url.appendingPathComponent("user.reg", isDirectory: false)
        guard fm.fileExists(atPath: regURL.path(percentEncoded: false)) else { return }

        let raw = try String(contentsOf: regURL, encoding: .utf8)
        var lines = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }

        let key = "[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Internet Settings]"
        let sectionStart = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(key) })

        func isSectionHeader(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.hasPrefix("[") && t.contains("]")
        }

        let server = state.port.isEmpty ? state.host : "\(state.host):\(state.port)"
        let enabled = state.enabled && !server.isEmpty
        let proxyEnableLine = String(format: #""ProxyEnable"=dword:%08x"#, enabled ? 1 : 0)

        var newSectionLines = [proxyEnableLine]
        if enabled {
            let escaped = server.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: #"\""#)
            newSectionLines.append("\"ProxyServer\"=\"\(escaped)\"")
        }

        if let start = sectionStart {
            let end = (lines[(start + 1)...].firstIndex(where: { isSectionHeader($0) }) ?? lines.endIndex)

            // Remove existing ProxyEnable/ProxyServer lines.
            var kept = [String]()
            kept.reserveCapacity(end - start)
            kept.append(lines[start])
            for i in (start + 1)..<end {
                let t = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("\"ProxyEnable\"") || t.hasPrefix("\"ProxyServer\"") {
                    continue
                }
                kept.append(lines[i])
            }

            // Insert our desired lines right after header.
            kept.insert(contentsOf: newSectionLines, at: 1)
            lines.replaceSubrange(start..<end, with: kept)
        } else {
            // Append section if missing.
            if let last = lines.last, !last.isEmpty {
                lines.append("")
            }
            lines.append(key)
            lines.append(contentsOf: newSectionLines)
        }

        try lines.joined(separator: "\r\n").write(to: regURL, atomically: true, encoding: .utf8)
    }
}
