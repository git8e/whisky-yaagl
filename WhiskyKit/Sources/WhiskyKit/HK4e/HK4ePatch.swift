//
//  HK4ePatch.swift
//  WhiskyKit
//

import Foundation

public enum HK4ePatch {
    private static var fm: FileManager { FileManager.default }
    private static let cloudArgs = ["-platform_type", "CLOUD_THIRD_PARTY_PC", "-is_cloud", "1"]

    private static func toWinePath(_ absPath: String) -> String {
        return "Z:" + absPath.replacingOccurrences(of: "/", with: "\\")
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
        let dir = bottle.url.appendingPathComponent("HK4e", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func stateURL(bottle: Bottle) throws -> URL {
        try workDir(bottle: bottle).appending(path: "patch-state.json")
    }

    private static func loadState(bottle: Bottle) -> HK4ePatchState? {
        do {
            let url = try stateURL(bottle: bottle)
            guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(HK4ePatchState.self, from: data)
        } catch {
            return nil
        }
    }

    private static func saveState(bottle: Bottle, state: HK4ePatchState) {
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

    public static func revertIfNeeded(bottle: Bottle, prefixURL: URL) async {
        guard let state = loadState(bottle: bottle), state.patched else { return }

        let gameDir = URL(fileURLWithPath: state.gameDir, isDirectory: true)
        let exeURL = URL(fileURLWithPath: state.executablePath, isDirectory: false)
        let info = HK4eGame.detect(executableURL: exeURL)

        if state.hdr {
            await HK4eHDR.revert(bottle: bottle, executableName: info.executableName)
        }
        if state.dxmt {
            HK4eDXMT.revertPrefix(prefixURL: prefixURL)
        }
        if state.removeCrashFiles {
            revertRemovedFiles(gameDir: gameDir, removed: HK4eGame.removedFiles(for: info))
        }

        clearState(bottle: bottle)
    }

    public static func applyAndRun(program: Program, args: [String], environment: [String: String]) async throws {
        let bottle = program.bottle
        let prefixURL = bottle.url
        let exeURL = program.url
        let gameDir = exeURL.deletingLastPathComponent()
        let info = HK4eGame.detect(executableURL: exeURL)

        await revertIfNeeded(bottle: bottle, prefixURL: prefixURL)

        if bottle.settings.hk4eLeftCommandIsCtrl || bottle.settings.hk4eCustomResolutionEnabled {
            try await HK4ePersistentConfig.applyIfNeeded(bottle: bottle)
        }

        try await HK4eDXMT.ensureInstalled()
        HK4eDXMT.applyToRuntime(runtimeId: bottle.settings.wineRuntimeId)
        try? HK4eDXMT.applyToPrefix(prefixURL: prefixURL)

        if bottle.settings.hk4eSteamPatch {
            try? await SteamPatch.apply(prefixURL: prefixURL)
        }

        patchRemovedFiles(gameDir: gameDir, removed: HK4eGame.removedFiles(for: info))

        if bottle.settings.hk4eEnableHDR {
            try? await HK4eHDR.apply(bottle: bottle, executableName: info.executableName)
        }

        let state = HK4ePatchState(
            patched: true,
            gameDir: gameDir.path(percentEncoded: false),
            executablePath: exeURL.path(percentEncoded: false),
            removeCrashFiles: true,
            dxmt: true,
            dxvk: false,
            reshade: false,
            hdr: bottle.settings.hk4eEnableHDR,
            resolution: false
        )
        saveState(bottle: bottle, state: state)

        var mergedEnv = environment
        // Match YAAGL defaults.
        mergedEnv["WINEDLLOVERRIDES"] = "d3d11,dxgi=n,b"

        await waitUntilServerOff(bottle: bottle)

        let work = try workDir(bottle: bottle)
        let batURL = work.appending(path: "hk4e_run.bat", directoryHint: .notDirectory)
        let exeWine = toWinePath(exeURL.path(percentEncoded: false))
        let dirWine = toWinePath(gameDir.path(percentEncoded: false))
        let hkProtectWine = toWinePath(gameDir.appendingPathComponent("HoYoKProtect.sys", isDirectory: false).path(percentEncoded: false))
        let joinedArgs = (cloudArgs + args).map(quoteForBatch).joined(separator: " ")

        let bat = """
        @echo off
        cd "%~dp0"
        if exist \(quoteForBatch(hkProtectWine)) copy /y \(quoteForBatch(hkProtectWine)) "%WINDIR%\\system32\\" >nul
        cd /d \"\(dirWine)\"
        \(quoteForBatch(exeWine)) \(joinedArgs)
        """
        try bat.write(to: batURL, atomically: true, encoding: .utf8)
        let batWine = toWinePath(batURL.path(percentEncoded: false))

        var exitCode: Int32 = 0
        do {
            let launchArgs: [String]
            if bottle.settings.hk4eSteamPatch {
                launchArgs = [#"C:\windows\system32\steam.exe"#, exeWine]
            } else {
                launchArgs = ["cmd", "/c", batWine]
            }

            for await output in try Wine.runWineProcess(
                name: exeURL.lastPathComponent,
                args: launchArgs,
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
            await postRevert(bottle: bottle, info: info, gameDir: gameDir, prefixURL: prefixURL, hdrApplied: state.hdr)
            throw error
        }

        await waitUntilServerOff(bottle: bottle)
        await postRevert(bottle: bottle, info: info, gameDir: gameDir, prefixURL: prefixURL, hdrApplied: state.hdr)
        try? fm.removeItem(at: batURL)

        if exitCode != 0 {
            throw HK4ePatchError.gameExited(code: Int(exitCode))
        }
    }

    private static func postRevert(
        bottle: Bottle,
        info: HK4eGame.Info,
        gameDir: URL,
        prefixURL: URL,
        hdrApplied: Bool
    ) async {
        if hdrApplied {
            await HK4eHDR.revert(bottle: bottle, executableName: info.executableName)
        }
        HK4eDXMT.revertPrefix(prefixURL: prefixURL)
        revertRemovedFiles(gameDir: gameDir, removed: HK4eGame.removedFiles(for: info))

        clearState(bottle: bottle)
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
}

public enum HK4ePatchError: LocalizedError {
    case gameExited(code: Int)

    public var errorDescription: String? {
        switch self {
        case .gameExited(let code):
            return "Game process exited with code \(code)"
        }
    }
}
