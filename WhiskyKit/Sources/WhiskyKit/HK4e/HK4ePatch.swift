//
//  HK4ePatch.swift
//  WhiskyKit
//

import Foundation

public enum HK4ePatch {
    private static var fm: FileManager { FileManager.default }

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
        if state.resolution {
            try? await HK4eResolution.revert(bottle: bottle)
        }
        if state.reshade {
            HK4eReShade.revertGameDir(gameDir: gameDir)
        }
        if state.dxvk {
            HK4eDXVK.revertPrefix(prefixURL: prefixURL)
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

        // Registry tweaks that should persist.
        try? await HK4eTweaks.setLeftCommandIsCtrl(bottle: bottle, enabled: bottle.settings.hk4eLeftCommandIsCtrl)
        if bottle.settings.hk4eEnableNVExtension {
            try? await HK4eTweaks.applyNVExtension(bottle: bottle)
        }

        // Pre-launch toggles.
        if bottle.settings.hk4eDXMTInjectionEnabled {
            try await HK4eDXMT.ensureInstalled()
            HK4eDXMT.applyToRuntime(runtimeId: bottle.settings.wineRuntimeId)
            try? HK4eDXMT.applyToPrefix(prefixURL: prefixURL)
        }

        if bottle.settings.hk4eDXVKInjectionEnabled {
            try await HK4eDXVK.ensureInstalled()
            try? HK4eDXVK.applyToPrefix(prefixURL: prefixURL)
        }

        if bottle.settings.hk4eReshadeEnabled {
            try await HK4eReShade.ensureInstalled()
            try? HK4eReShade.applyToGameDir(gameDir: gameDir)
        }

        if bottle.settings.hk4eSteamPatch {
            try? await SteamPatch.apply(prefixURL: prefixURL)
        }

        if bottle.settings.hk4eRemoveCrashFiles {
            patchRemovedFiles(gameDir: gameDir, removed: HK4eGame.removedFiles(for: info))
        }

        if bottle.settings.hk4eEnableHDR {
            try? await HK4eHDR.apply(bottle: bottle, executableName: info.executableName)
        }

        if bottle.settings.hk4eCustomResolutionEnabled {
            try? await HK4eResolution.apply(
                bottle: bottle,
                width: bottle.settings.hk4eCustomResolutionWidth,
                height: bottle.settings.hk4eCustomResolutionHeight,
                executableName: info.executableName
            )
        }

        let state = HK4ePatchState(
            patched: true,
            gameDir: gameDir.path(percentEncoded: false),
            executablePath: exeURL.path(percentEncoded: false),
            removeCrashFiles: bottle.settings.hk4eRemoveCrashFiles,
            dxmt: bottle.settings.hk4eDXMTInjectionEnabled,
            dxvk: bottle.settings.hk4eDXVKInjectionEnabled,
            reshade: bottle.settings.hk4eReshadeEnabled,
            hdr: bottle.settings.hk4eEnableHDR,
            resolution: bottle.settings.hk4eCustomResolutionEnabled
        )
        saveState(bottle: bottle, state: state)

        var mergedEnv = environment
        if bottle.settings.hk4eDXMTInjectionEnabled || bottle.settings.hk4eDXVKInjectionEnabled {
            // Match YAAGL defaults.
            mergedEnv["WINEDLLOVERRIDES"] = "d3d11,dxgi=n,b"
        }

        do {
            try await Wine.runProgram(at: exeURL, args: args, bottle: bottle, environment: mergedEnv)
            await postRevert(bottle: bottle, info: info, gameDir: gameDir, prefixURL: prefixURL)
        } catch {
            await postRevert(bottle: bottle, info: info, gameDir: gameDir, prefixURL: prefixURL)
            throw error
        }
    }

    private static func postRevert(bottle: Bottle, info: HK4eGame.Info, gameDir: URL, prefixURL: URL) async {
        if bottle.settings.hk4eEnableHDR {
            await HK4eHDR.revert(bottle: bottle, executableName: info.executableName)
        }
        if bottle.settings.hk4eCustomResolutionEnabled {
            try? await HK4eResolution.revert(bottle: bottle)
        }
        if bottle.settings.hk4eReshadeEnabled {
            HK4eReShade.revertGameDir(gameDir: gameDir)
        }
        if bottle.settings.hk4eDXVKInjectionEnabled {
            HK4eDXVK.revertPrefix(prefixURL: prefixURL)
        }
        if bottle.settings.hk4eDXMTInjectionEnabled {
            HK4eDXMT.revertPrefix(prefixURL: prefixURL)
        }
        if bottle.settings.hk4eRemoveCrashFiles {
            revertRemovedFiles(gameDir: gameDir, removed: HK4eGame.removedFiles(for: info))
        }

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
