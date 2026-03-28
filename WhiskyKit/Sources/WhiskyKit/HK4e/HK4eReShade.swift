//
//  HK4eReShade.swift
//  WhiskyKit
//

import Foundation

public enum HK4eReShade {
    private static var fm: FileManager { FileManager.default }

    private static let version = "5.8.0"

    private static let setupURL = URL(
        string: "https://reshade.me/downloads/ReShade_Setup_\(version)_Addon.exe"
    )!

    private static let compilerURL = URL(
        string: "https://lutris.net/files/tools/dll/d3dcompiler_47.dll"
    )!

    private static func toWinePath(_ absPath: String) -> String {
        return "Z:" + absPath.replacingOccurrences(of: "/", with: "\\")
    }

    public static func ensureInstalled(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try HK4eResources.ensureDirs()

        let dir = HK4eResources.reshadeDir
        let setupExe = dir.appending(path: "install.exe")
        let compiler = dir.appending(path: "d3dcompiler_47.dll")

        var p1: (@Sendable (Double) -> Void)?
        var p2: (@Sendable (Double) -> Void)?
        if let cb = progress {
            p1 = { frac in cb(frac * 0.7) }
            p2 = { frac in cb(0.7 + frac * 0.3) }
        }

        try await RemoteDownloader.downloadOnce(url: setupURL, destination: setupExe, progress: p1)
        try await RemoteDownloader.downloadOnce(url: compilerURL, destination: compiler, progress: p2)

        // Extract embedded zip from the setup EXE.
        let zipURL = dir.appending(path: "install.zip")
        if !fm.fileExists(atPath: zipURL.path(percentEncoded: false)) {
            try extractZipFromExe(exeURL: setupExe, zipURL: zipURL)
        }

        // Extract archive to dir (idempotent).
        try? HK4eZip.extract(zipURL: zipURL, to: dir)

        // Normalize output: ReShade64.dll -> dxgi.dll
        let reshade64 = dir.appending(path: "ReShade64.dll")
        let dxgi = dir.appending(path: "dxgi.dll")
        if fm.fileExists(atPath: reshade64.path(percentEncoded: false)), !fm.fileExists(atPath: dxgi.path(percentEncoded: false)) {
            try? fm.moveItem(at: reshade64, to: dxgi)
        }

        // Ensure shaders folders exist.
        for sub in ["Shaders", "Textures"] {
            let p = dir.appending(path: sub, directoryHint: .isDirectory)
            if !fm.fileExists(atPath: p.path(percentEncoded: false)) {
                try? fm.createDirectory(at: p, withIntermediateDirectories: true)
            }
        }
    }

    public static func applyToGameDir(gameDir: URL) throws {
        let dir = HK4eResources.reshadeDir
        let dxgi = dir.appending(path: "dxgi.dll")
        let compiler = dir.appending(path: "d3dcompiler_47.dll")
        guard fm.fileExists(atPath: dxgi.path(percentEncoded: false)) else { return }

        let dstDxgi = gameDir.appending(path: "dxgi.dll")
        let dstCompiler = gameDir.appending(path: "d3dcompiler_47.dll")

        if fm.fileExists(atPath: dstDxgi.path(percentEncoded: false)) {
            try? fm.removeItem(at: dstDxgi)
        }
        try? FileCopy.copyItem(at: dxgi, to: dstDxgi, replacing: true)

        if fm.fileExists(atPath: compiler.path(percentEncoded: false)) {
            if fm.fileExists(atPath: dstCompiler.path(percentEncoded: false)) {
                try? fm.removeItem(at: dstCompiler)
            }
            try? FileCopy.copyItem(at: compiler, to: dstCompiler, replacing: true)
        }

        // Write ReShade.ini so it can find shaders.
        let shadersWine = toWinePath(dir.appending(path: "Shaders").path(percentEncoded: false))
        let texturesWine = toWinePath(dir.appending(path: "Textures").path(percentEncoded: false))
        let ini = """
[GENERAL]
EffectSearchPaths=\(shadersWine)
TextureSearchPaths=\(texturesWine)
"""
        try? ini.write(to: gameDir.appending(path: "ReShade.ini"), atomically: true, encoding: .utf8)
    }

    public static func revertGameDir(gameDir: URL) {
        for name in ["dxgi.dll", "d3dcompiler_47.dll", "ReShade.ini"] {
            let url = gameDir.appending(path: name)
            if fm.fileExists(atPath: url.path(percentEncoded: false)) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private static func extractZipFromExe(exeURL: URL, zipURL: URL) throws {
        let data = try Data(contentsOf: exeURL)
        // ZIP local header magic: PK\x03\x04
        let sig: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        guard let offset = data.range(of: Data(sig))?.lowerBound else {
            throw HK4eReShadeError.zipSignatureNotFound
        }
        let zipData = data.suffix(from: offset)
        try zipData.write(to: zipURL)
    }
}

public enum HK4eReShadeError: LocalizedError {
    case zipSignatureNotFound

    public var errorDescription: String? {
        switch self {
        case .zipSignatureNotFound:
            return "Failed to locate embedded zip inside ReShade setup"
        }
    }
}
