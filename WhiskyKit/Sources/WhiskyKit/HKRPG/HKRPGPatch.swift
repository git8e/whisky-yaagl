//
//  HKRPGPatch.swift
//  WhiskyKit
//

import Foundation

public enum HKRPGPatch {
    private static var fm: FileManager { FileManager.default }
    private static let launchFixBlockNetworkSeconds: UInt64 = 15
    private static let launchFixProxyHost = "127.0.0.1"
    private static let launchFixProxyPort = "1"

    private static func toWinePath(_ absPath: String) -> String {
        "Z:" + absPath.replacingOccurrences(of: "/", with: "\\")
    }

    private static func quoteForBatch(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func waitUntilServerOff(bottle: Bottle) async {
        do {
            for await _ in try Wine.runWineserverProcess(args: ["-w"], bottle: bottle) { }
        } catch {
            // best-effort
        }
    }

    private static func workDir(bottle: Bottle) throws -> URL {
        let dir = bottle.url.appendingPathComponent("HKRPG", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func stateURL(bottle: Bottle) throws -> URL {
        try workDir(bottle: bottle).appending(path: "patch-state.json")
    }

    private static func loadState(bottle: Bottle) -> HKRPGPatchState? {
        do {
            let url = try stateURL(bottle: bottle)
            guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(HKRPGPatchState.self, from: data)
        } catch {
            return nil
        }
    }

    private static func saveState(bottle: Bottle, state: HKRPGPatchState) {
        do {
            let url = try stateURL(bottle: bottle)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url)
        } catch {
            // ignore
        }
    }

    private static func clearState(bottle: Bottle) {
        do {
            let url = try stateURL(bottle: bottle)
            if fm.fileExists(atPath: url.path(percentEncoded: false)) {
                try? fm.removeItem(at: url)
            }
        } catch {
            // ignore
        }
    }

    private static func patchRemovedFiles(gameDir: URL, removed: [String]) {
        for rel in removed {
            let url = gameDir.appendingPathComponent(rel, isDirectory: false)
            let bak = URL(fileURLWithPath: url.path(percentEncoded: false) + ".bak")
            guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            if !fm.fileExists(atPath: bak.path(percentEncoded: false)) {
                try? fm.moveItem(at: url, to: bak)
            }
        }
    }

    private static func revertRemovedFiles(gameDir: URL, removed: [String]) {
        for rel in removed {
            let url = gameDir.appendingPathComponent(rel, isDirectory: false)
            let bak = URL(fileURLWithPath: url.path(percentEncoded: false) + ".bak")
            guard fm.fileExists(atPath: bak.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: url.path(percentEncoded: false)) {
                try? fm.removeItem(at: url)
            }
            try? fm.moveItem(at: bak, to: url)
        }
    }

    public static func revertIfNeeded(bottle: Bottle, prefixURL: URL) async {
        guard let state = loadState(bottle: bottle), state.patched else { return }

        let gameDir = URL(fileURLWithPath: state.gameDir, isDirectory: true)
        if state.removedFiles {
            revertRemovedFiles(gameDir: gameDir, removed: HKRPGGame.removedFiles())
        }

        clearState(bottle: bottle)
    }

    private static func postRevert(bottle: Bottle, gameDir: URL, prefixURL: URL, state: HKRPGPatchState) async {
        if state.removedFiles {
            revertRemovedFiles(gameDir: gameDir, removed: HKRPGGame.removedFiles())
        }
        clearState(bottle: bottle)
    }

    public static func applyAndRun(program: Program, args: [String], environment: [String: String]) async throws {
        let bottle = program.bottle
        let prefixURL = bottle.url
        let exeURL = program.url
        let gameDir = exeURL.deletingLastPathComponent()

        let runtimeId = bottle.settings.wineRuntimeId
        let runtime = WineRuntimes.runtime(id: runtimeId)
        let usesDXMT = (runtime?.renderBackend == .dxmt)
        let supportsPatching = (runtime != nil) && (runtimeId != WineRuntimes.whiskyDefaultId)

        try await WineRuntimeManager.ensureIsolatedRuntime(bottle: bottle, baseRuntimeId: runtimeId)
        await revertIfNeeded(bottle: bottle, prefixURL: prefixURL)

        if bottle.settings.hkrpgFixWebview {
            await HKRPGWebviewFix.applyIfNeeded(bottle: bottle, region: bottle.settings.hkrpgRegion)
        }
        if usesDXMT {
            // Mirrors YAAGL: set NV extension when using DXMT.
            try? await HKRPGTweaks.applyNVExtension(bottle: bottle)

            // Ensure DXMT files are present and applied.
            try? await HKRPGDXMT.ensureInstalled()
            HKRPGDXMT.applyToRuntime(runtimeRoot: WineRuntimeManager.effectiveWineRoot(bottle: bottle))
            try? HKRPGDXMT.applyToPrefix(prefixURL: prefixURL)
        }

        let state: HKRPGPatchState?
        if supportsPatching, bottle.settings.hkrpgLaunchPatchingEnabled {
            patchRemovedFiles(gameDir: gameDir, removed: HKRPGGame.removedFiles())
            let s = HKRPGPatchState(
                patched: true,
                gameDir: gameDir.path(percentEncoded: false),
                executablePath: exeURL.path(percentEncoded: false),
                removedFiles: true
            )
            saveState(bottle: bottle, state: s)
            state = s
        } else {
            state = nil
        }

        var mergedEnv = environment
        if usesDXMT {
            // Match YAAGL's HKRPG DXMT environment defaults.
            mergedEnv["DXMT_CONFIG"] = "d3d11.preferredMaxFrameRate=60;dxgi.customVendorId=10de;dxgi.customDeviceId=2684"
            mergedEnv["DXMT_ENABLE_NVEXT"] = "1"
            if HKRPGDXMT.useNativeDlls() {
                mergedEnv["WINEDLLOVERRIDES"] = "d3d11,dxgi=n,b"
            }
        }

        await waitUntilServerOff(bottle: bottle)

        // Ensure Jadeite is installed into the prefix.
        try await HKRPGJadeite.ensureInstalled(bottle: bottle)

        let work = try workDir(bottle: bottle)
        let batURL = work.appending(path: "hkrpg_run.bat", directoryHint: .notDirectory)
        let dirWine = toWinePath(gameDir.path(percentEncoded: false))
        let exeWine = toWinePath(exeURL.path(percentEncoded: false))

        let forwardedArgs = args.map(quoteForBatch).joined(separator: " ")
        let jadeite = #"C:\jadeite\jadeite.exe"#
        let extra = forwardedArgs.isEmpty ? "" : " \(forwardedArgs)"
        let bat = """
        @echo off
        cd "%~dp0"
        cd /d \"\(dirWine)\"
        \(jadeite) \(quoteForBatch(exeWine)) -- -disable-gpu-skinning\(extra)
        """
        try bat.write(to: batURL, atomically: true, encoding: .utf8)
        let batWine = toWinePath(batURL.path(percentEncoded: false))

        var exitCode: Int32 = 0
        do {
            if bottle.settings.hkrpgLaunchFixBlockNetwork {
                let host = bottle.settings.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
                let port = bottle.settings.proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
                let server = port.isEmpty ? host : "\(host):\(port)"
                let existingProxyEnabled = bottle.settings.proxyEnabled && !server.isEmpty

                if !existingProxyEnabled {
                    try? await WineProxySettings.applyTemporaryOverride(
                        bottle: bottle,
                        enabled: true,
                        host: launchFixProxyHost,
                        port: launchFixProxyPort
                    )
                    Task.detached(priority: .utility) {
                        try? await Task.sleep(nanoseconds: launchFixBlockNetworkSeconds * 1_000_000_000)
                        try? await WineProxySettings.restoreDesiredState(bottle: bottle)
                    }
                }
            }

            for await output in try Wine.runWineProcess(
                name: exeURL.lastPathComponent,
                args: ["cmd", "/c", batWine],
                bottle: bottle,
                environment: mergedEnv,
                directory: work
            ) {
                if case .terminated(let p) = output {
                    exitCode = p.terminationStatus
                }
            }
        } catch {
            await waitUntilServerOff(bottle: bottle)
            if let state {
                await postRevert(bottle: bottle, gameDir: gameDir, prefixURL: prefixURL, state: state)
            }
            throw error
        }

        await waitUntilServerOff(bottle: bottle)
        if let state {
            await postRevert(bottle: bottle, gameDir: gameDir, prefixURL: prefixURL, state: state)
        }
        try? fm.removeItem(at: batURL)

        if exitCode != 0 {
            throw HKRPGPatchError.gameExited(code: Int(exitCode))
        }
    }
}

public enum HKRPGPatchError: LocalizedError {
    case gameExited(code: Int)

    public var errorDescription: String? {
        switch self {
        case .gameExited(let code):
            return "Game exited with code \(code)"
        }
    }
}
