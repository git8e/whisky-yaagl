//
//  NAPPatch.swift
//  WhiskyKit
//

import Foundation

public enum NAPPatch {
    private static var fm: FileManager { FileManager.default }
    private static let launchFixBlockNetworkSeconds: UInt64 = 10
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
        let dir = bottle.url.appendingPathComponent("NAP", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func patchRemovedFiles(gameDir: URL, removed: [String]) {
        for rel in removed {
            let src = gameDir.appendingPathComponent(rel, isDirectory: false)
            let bak = gameDir.appendingPathComponent(rel + ".bak", isDirectory: false)
            guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: bak.path(percentEncoded: false)) { continue }
            try? fm.createDirectory(at: bak.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: src, to: bak)
        }
    }

    private static func revertRemovedFiles(gameDir: URL, removed: [String]) {
        for rel in removed {
            let src = gameDir.appendingPathComponent(rel, isDirectory: false)
            let bak = gameDir.appendingPathComponent(rel + ".bak", isDirectory: false)
            guard fm.fileExists(atPath: bak.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: src.path(percentEncoded: false)) {
                try? fm.removeItem(at: src)
            }
            try? fm.moveItem(at: bak, to: src)
        }
    }

    public static func applyAndRun(program: Program, args: [String], environment: [String: String]) async throws {
        let bottle = program.bottle
        try await WineRuntimeManager.ensureIsolatedRuntime(bottle: bottle, baseRuntimeId: bottle.settings.wineRuntimeId)
        let exeURL = program.url
        let gameDir = exeURL.deletingLastPathComponent()
        let region = bottle.settings.napRegion

        let runtime = WineRuntimes.runtime(id: bottle.settings.wineRuntimeId)
        let usesDXMT = (runtime?.renderBackend == .dxmt)

        let removedFiles = NapGame.removedFiles(executableURL: exeURL)
        patchRemovedFiles(gameDir: gameDir, removed: removedFiles)
        defer { revertRemovedFiles(gameDir: gameDir, removed: removedFiles) }

        if bottle.settings.napFixWebview {
            await NapWebviewFix.applyIfNeeded(bottle: bottle, region: region)
        }

        if usesDXMT {
            try? await NAPDXMT.ensureInstalled()
            NAPDXMT.applyToRuntime(runtimeRoot: WineRuntimeManager.effectiveWineRoot(bottle: bottle))
            try? NAPDXMT.applyToPrefix(prefixURL: bottle.url)
        }

        var mergedEnv = environment
        if usesDXMT && NAPDXMT.useNativeDlls() {
            mergedEnv["WINEDLLOVERRIDES"] = "d3d11,dxgi=n,b"
        }

        var resolutionArgs: [String] = []
        if bottle.settings.napCustomResolutionEnabled,
           bottle.settings.napCustomResolutionWidth > 0,
           bottle.settings.napCustomResolutionHeight > 0 {
            resolutionArgs = [
                "-screen-width",
                String(bottle.settings.napCustomResolutionWidth),
                "-screen-height",
                String(bottle.settings.napCustomResolutionHeight),
                "-screen-fullscreen",
                "0"
            ]
        }

        await waitUntilServerOff(bottle: bottle)

        let work = try workDir(bottle: bottle)
        let batURL = work.appending(path: "nap_run.bat", directoryHint: .notDirectory)
        defer { try? fm.removeItem(at: batURL) }
        let exeWine = toWinePath(exeURL.path(percentEncoded: false))
        let dirWine = toWinePath(gameDir.path(percentEncoded: false))
        let hkProtectWine = toWinePath(
            gameDir.appendingPathComponent("HoYoKProtect.sys", isDirectory: false).path(percentEncoded: false)
        )
        let joinedArgs = (resolutionArgs + args).map(quoteForBatch).joined(separator: " ")

        let bat = """
        @echo off
        cd "%~dp0"
        if exist \(quoteForBatch(hkProtectWine)) copy /y \(quoteForBatch(hkProtectWine)) "%WINDIR%\\system32\\" >nul
        cd /d "\(dirWine)"
        \(quoteForBatch(exeWine)) \(joinedArgs)
        """
        try bat.write(to: batURL, atomically: true, encoding: .utf8)
        let batWine = toWinePath(batURL.path(percentEncoded: false))

        var exitCode: Int32 = 0
        do {
            if bottle.settings.napLaunchFixBlockNetwork {
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
            if bottle.settings.napCustomResolutionEnabled {
                await NapResolution.revertIfNeeded(bottle: bottle, region: region)
            }
            throw error
        }

        await waitUntilServerOff(bottle: bottle)
        if bottle.settings.napCustomResolutionEnabled {
            await NapResolution.revertIfNeeded(bottle: bottle, region: region)
        }

        if exitCode != 0 {
            throw NAPPatchError.gameExited(code: Int(exitCode))
        }
    }
}

public enum NAPPatchError: LocalizedError {
    case gameExited(code: Int)

    public var errorDescription: String? {
        switch self {
        case .gameExited(let code):
            return "Game process exited with code \(code)"
        }
    }
}
