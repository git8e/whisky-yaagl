//
//  Wine.swift
//  Whisky
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
import os.log

public class Wine {
    @TaskLocal public static var currentLogSessionURL: URL?

    /// URL to the installed `DXVK` folder
    private static let dxvkFolder: URL = WhiskyWineInstaller.libraryFolder.appending(path: "DXVK")
    /// Path to the default `wine64` binary
    private static let defaultWineBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wine64")
    /// Path to the default `wineserver` binary
    private static let defaultWineserverBinary: URL = WhiskyWineInstaller.binFolder.appending(path: "wineserver")

    /// Run a process on a executable file given by the `executableURL`
    private static func runProcess(
        name: String? = nil, args: [String], environment: [String: String], executableURL: URL, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = args
        process.currentDirectoryURL = directory ?? executableURL.deletingLastPathComponent()
        process.environment = environment
        process.qualityOfService = .userInitiated

        return try process.runStream(
            name: name ?? args.joined(separator: " "), fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    private static func runWineProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        executableURL: URL = defaultWineBinary, directory: URL? = nil,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: executableURL,
            directory: directory,
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    private static func runWineserverProcess(
        name: String? = nil, args: [String], environment: [String: String] = [:],
        executableURL: URL = defaultWineserverBinary,
        fileHandle: FileHandle?
    ) throws -> AsyncStream<ProcessOutput> {
        return try runProcess(
            name: name, args: args, environment: environment, executableURL: executableURL,
            fileHandle: fileHandle
        )
    }

    /// Run a `wine` process with the given arguments and environment variables returning a stream of output
    public static func runWineProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:], directory: URL? = nil
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        if Self.currentLogSessionURL == nil {
            fileHandle.writeApplicaitonInfo()
            fileHandle.writeInfo(for: bottle)
        }

        let wineBinary = WineRuntimeManager.wineBinary(bottle: bottle)

        return try runWineProcess(
            name: name, args: args,
            environment: constructWineEnvironment(for: bottle, environment: environment),
            executableURL: wineBinary,
            directory: directory,
            fileHandle: fileHandle
        )
    }

    /// Run a `wineserver` process with the given arguments and environment variables returning a stream of output
    public static func runWineserverProcess(
        name: String? = nil, args: [String], bottle: Bottle, environment: [String: String] = [:]
    ) throws -> AsyncStream<ProcessOutput> {
        let fileHandle = try makeFileHandle()
        if Self.currentLogSessionURL == nil {
            fileHandle.writeApplicaitonInfo()
            fileHandle.writeInfo(for: bottle)
        }

        let wineserverBinary = WineRuntimeManager.wineserverBinary(bottle: bottle)

        return try runWineserverProcess(
            name: name, args: args,
            environment: constructWineServerEnvironment(for: bottle, environment: environment),
            executableURL: wineserverBinary,
            fileHandle: fileHandle
        )
    }

    /// Execute a `wine start /unix {url}` command returning the output result
    public static func runProgram(
        at url: URL, args: [String] = [], bottle: Bottle, environment: [String: String] = [:]
    ) async throws {
        if bottle.settings.dxvk {
            try enableDXVK(bottle: bottle)
        }

        for await _ in try Self.runWineProcess(
            name: url.lastPathComponent,
            args: ["start", "/unix", url.path(percentEncoded: false)] + args,
            bottle: bottle, environment: environment
        ) { }
    }

    public static func generateRunCommand(
        at url: URL, bottle: Bottle, args: String, environment: [String: String]
    ) -> String {
        let wineBinary = WineRuntimeManager.wineBinary(bottle: bottle)
        var wineCmd = "\(wineBinary.esc) start /unix \(url.esc) \(args)"
        let env = constructWineEnvironment(for: bottle, environment: environment)
        for environment in env {
            wineCmd = "\(environment.key)=\"\(environment.value)\" " + wineCmd
        }

        return wineCmd
    }

    public static func generateTerminalEnvironmentCommand(bottle: Bottle) -> String {
        let binFolder = WineRuntimeManager.binFolder(bottle: bottle)
        let wineBinaryName = WineRuntimeManager.wineBinary(bottle: bottle).lastPathComponent
        var cmd = """
        export PATH=\"\(binFolder.path):$PATH\"
        export WINE=\"\(wineBinaryName)\"
        alias wine=\"\(wineBinaryName)\"
        alias winecfg=\"\(wineBinaryName) winecfg\"
        alias msiexec=\"\(wineBinaryName) msiexec\"
        alias regedit=\"\(wineBinaryName) regedit\"
        alias regsvr32=\"\(wineBinaryName) regsvr32\"
        alias wineboot=\"\(wineBinaryName) wineboot\"
        alias wineconsole=\"\(wineBinaryName) wineconsole\"
        alias winedbg=\"\(wineBinaryName) winedbg\"
        alias winefile=\"\(wineBinaryName) winefile\"
        alias winepath=\"\(wineBinaryName) winepath\"
        """

        let env = constructWineEnvironment(for: bottle, environment: constructWineEnvironment(for: bottle))
        for environment in env {
            cmd += "\nexport \(environment.key)=\"\(environment.value)\""
        }

        return cmd
    }

    /// Run a `wineserver` command with the given arguments and return the output result
    private static func runWineserver(_ args: [String], bottle: Bottle) async throws -> String {
        var result: [ProcessOutput] = []

        for await output in try Self.runWineserverProcess(args: args, bottle: bottle, environment: [:]) {
            result.append(output)
        }

        return result.compactMap { output -> String? in
            switch output {
            case .started, .terminated:
                return nil
            case .message(let message), .error(let message):
                return message
            }
        }.joined()
    }

    @discardableResult
    /// Run a `wine` command with the given arguments and return the output result
    public static func runWine(
        _ args: [String], bottle: Bottle?, environment: [String: String] = [:], log: Bool = true
    ) async throws -> String {
        var result: [String] = []
        let fileHandle = log ? try makeFileHandle() : nil
        var environment = environment

        if log, Self.currentLogSessionURL == nil {
            fileHandle?.writeApplicaitonInfo()
        }

        if let bottle = bottle {
            // Ensure runtime isolation before any Wine command runs.
            try await WineRuntimeManager.ensureIsolatedRuntime(
                bottle: bottle,
                baseRuntimeId: bottle.settings.wineRuntimeId
            )
            if log, Self.currentLogSessionURL == nil {
                fileHandle?.writeInfo(for: bottle)
            }
            environment = constructWineEnvironment(for: bottle, environment: environment)
        }

        let executableURL: URL = {
            if let bottle {
                return WineRuntimeManager.wineBinary(bottle: bottle)
            }
            return defaultWineBinary
        }()

        for await output in try runWineProcess(
            args: args,
            environment: environment,
            executableURL: executableURL,
            fileHandle: fileHandle
        ) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }

        return result.joined()
    }

    public static func wineVersion() async throws -> String {
        var output = try await runWine(["--version"], bottle: nil)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func wineVersion(bottle: Bottle) async throws -> String {
        var output = try await runWine(["--version"], bottle: bottle)
        output.replace("wine-", with: "")

        // Deal with WineCX version names
        if let index = output.firstIndex(where: { $0.isWhitespace }) {
            return String(output.prefix(upTo: index))
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public static func runBatchFile(url: URL, bottle: Bottle) async throws -> String {
        return try await runWine(["cmd", "/c", url.path(percentEncoded: false)], bottle: bottle)
    }

    public static func killBottle(bottle: Bottle) throws {
        Task.detached(priority: .userInitiated) {
            try await runWineserver(["-k"], bottle: bottle)
        }
    }

    public static func enableDXVK(bottle: Bottle) throws {
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "system32"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x64")
        )
        try FileManager.default.replaceDLLs(
            in: bottle.url.appending(path: "drive_c").appending(path: "windows").appending(path: "syswow64"),
            withContentsIn: Wine.dxvkFolder.appending(path: "x32")
        )
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        if let runtime = WineRuntimes.runtime(id: bottle.settings.wineRuntimeId), runtime.renderBackend == .dxmt {
            result["DXMT_LOG_PATH"] = WhiskyPaths.applicationSupportRoot.path(percentEncoded: false)
            result["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;"
            // Keep DXMT config per-bottle to avoid cross-bottle side effects.
            result["DXMT_CONFIG_FILE"] = bottle.url.appending(path: "dxmt.conf").path(percentEncoded: false)
            result["GST_PLUGIN_FEATURE_RANK"] = "atdec:MAX,avdec_h264:MAX"
        }
        bottle.settings.environmentVariables(wineEnv: &result)
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }

    /// Construct an environment merging the bottle values with the given values
    private static func constructWineServerEnvironment(
        for bottle: Bottle, environment: [String: String] = [:]
    ) -> [String: String] {
        var result: [String: String] = [
            "WINEPREFIX": bottle.url.path,
            "WINEDEBUG": "fixme-all",
            "GST_DEBUG": "1"
        ]
        guard !environment.isEmpty else { return result }
        result.merge(environment, uniquingKeysWith: { $1 })
        return result
    }
}

enum WineInterfaceError: Error {
    case invalidResponce
}

enum RegistryType: String {
    case binary = "REG_BINARY"
    case dword = "REG_DWORD"
    case qword = "REG_QWORD"
    case string = "REG_SZ"
}

extension Wine {
    public static let logsFolder = WhiskyPaths.logsRoot

    public static func withLogSession<T>(for bottle: Bottle?, operation: () async throws -> T) async throws -> T {
        if Self.currentLogSessionURL != nil {
            return try await operation()
        }

        let sessionURL = try createLogSessionURL(bottle: bottle)
        return try await Self.$currentLogSessionURL.withValue(sessionURL) {
            try await operation()
        }
    }

    public static func latestLogFileURL() -> URL? {
        let fm = FileManager.default
        let logsPath = logsFolder.path(percentEncoded: false)
        guard fm.fileExists(atPath: logsPath) else { return nil }
        do {
            let urls = try fm.contentsOfDirectory(at: logsFolder, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "log" }
            return urls.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 < d2
            }.last
        } catch {
            return nil
        }
    }

    public static func makeFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: Self.logsFolder.path) {
            try FileManager.default.createDirectory(at: Self.logsFolder, withIntermediateDirectories: true)
        }

        if let sessionURL = Self.currentLogSessionURL {
            let handle = try FileHandle(forWritingTo: sessionURL)
            try handle.seekToEnd()
            return handle
        }

        let fileURL = nextLogFileURL()
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        return try FileHandle(forWritingTo: fileURL)
    }

    private static func createLogSessionURL(bottle: Bottle?) throws -> URL {
        let fileURL = nextLogFileURL()
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.writeApplicaitonInfo()
        if let bottle {
            fileHandle.writeInfo(for: bottle)
        }
        try fileHandle.close()
        return fileURL
    }

    private static func nextLogFileURL() -> URL {
        let dateString = Date.now.ISO8601Format()
        return Self.logsFolder.appending(path: dateString).appendingPathExtension("log")
    }
}

extension Wine {
    private enum RegistryKey: String {
        case currentVersion = #"HKLM\Software\Microsoft\Windows NT\CurrentVersion"#
        case macDriver = #"HKCU\Software\Wine\Mac Driver"#
        case desktop = #"HKCU\Control Panel\Desktop"#
    }

    private static func addRegistryKey(
        bottle: Bottle, key: String, name: String, data: String, type: RegistryType
    ) async throws {
        try await runWine(
            ["reg", "add", key, "-v", name, "-t", type.rawValue, "-d", data, "-f"],
            bottle: bottle
        )
    }

    private static func queryRegistryKey(
        bottle: Bottle, key: String, name: String, type: RegistryType
    ) async throws -> String? {
        let output = try await runWine(["reg", "query", key, "-v", name], bottle: bottle, log: false)
        if output.contains("Unable to find the specified registry value") ||
            output.contains("Unable to access or create the specified registry key") ||
            output.contains("Invalid system key") {
            return nil
        }
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)

        guard let line = lines.first(where: { $0.contains(type.rawValue) }) else { return nil }
        let array = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let value = array.last else { return nil }
        return String(value)
    }

    public static func changeBuildVersion(bottle: Bottle, version: Int) async throws {
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuild", data: "\(version)", type: .string)
        try await addRegistryKey(bottle: bottle, key: RegistryKey.currentVersion.rawValue,
                                name: "CurrentBuildNumber", data: "\(version)", type: .string)
    }

    public static func winVersion(bottle: Bottle) async throws -> WinVersion {
        let output = try await Wine.runWine(["winecfg", "-v"], bottle: bottle)
        let lines = output.split(whereSeparator: \.isNewline)

        if let lastLine = lines.last {
            let winString = String(lastLine)

            if let version = WinVersion(rawValue: winString) {
                return version
            }
        }

        throw WineInterfaceError.invalidResponce
    }

    public static func buildVersion(bottle: Bottle) async throws -> String? {
        return try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.currentVersion.rawValue,
            name: "CurrentBuild", type: .string
        )
    }

    public static func retinaMode(bottle: Bottle) async throws -> Bool {
        let values: Set<String> = ["y", "n"]
        guard let output = try await Wine.queryRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", type: .string
        ), values.contains(output) else {
            try await changeRetinaMode(bottle: bottle, retinaMode: false)
            return false
        }
        return output == "y"
    }

    public static func changeRetinaMode(bottle: Bottle, retinaMode: Bool) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.macDriver.rawValue, name: "RetinaMode", data: retinaMode ? "y" : "n",
            type: .string
        )
    }

    public static func dpiResolution(bottle: Bottle) async throws -> Int? {
        guard let output = try await Wine.queryRegistryKey(bottle: bottle, key: RegistryKey.desktop.rawValue,
                                                     name: "LogPixels", type: .dword
        ) else { return nil }

        let noPrefix = output.replacingOccurrences(of: "0x", with: "")
        let int = Int(noPrefix, radix: 16)
        guard let int = int else { return nil }
        return int
    }

    public static func changeDpiResolution(bottle: Bottle, dpi: Int) async throws {
        try await Wine.addRegistryKey(
            bottle: bottle, key: RegistryKey.desktop.rawValue, name: "LogPixels", data: String(dpi),
            type: .dword
        )
    }

    @discardableResult
    public static func control(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["control"], bottle: bottle)
    }

    @discardableResult
    public static func regedit(bottle: Bottle) async throws -> String {
        let fileHandle = try makeFileHandle()
        if Self.currentLogSessionURL == nil {
            fileHandle.writeApplicaitonInfo()
            fileHandle.writeInfo(for: bottle)
        }

        let regeditBinary = WineRuntimeManager.binFolder(bottle: bottle).appending(path: "regedit")
        let executableURL = FileManager.default.fileExists(atPath: regeditBinary.path(percentEncoded: false))
            ? regeditBinary
            : WineRuntimeManager.wineBinary(bottle: bottle)
        let args: [String] = executableURL == regeditBinary ? [] : ["regedit"]

        var result: [String] = []
        for await output in try runProcess(
            name: "regedit",
            args: args,
            environment: constructWineEnvironment(for: bottle),
            executableURL: executableURL,
            fileHandle: fileHandle
        ) {
            switch output {
            case .started, .terminated:
                break
            case .message(let message), .error(let message):
                result.append(message)
            }
        }
        return result.joined()
    }

    @discardableResult
    public static func cfg(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["winecfg"], bottle: bottle)
    }

    @discardableResult
    public static func taskManager(bottle: Bottle) async throws -> String {
        return try await Wine.runWine(["taskmgr"], bottle: bottle)
    }

    @discardableResult
    public static func changeWinVersion(bottle: Bottle, win: WinVersion) async throws -> String {
        return try await Wine.runWine(["winecfg", "-v", win.rawValue], bottle: bottle)
    }
}
