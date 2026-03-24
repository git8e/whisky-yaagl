//
//  HK4eDXMT.swift
//  WhiskyKit
//

import Foundation

public enum HK4eDXMT {
    private static var fm: FileManager { FileManager.default }

    public static let dxmtFiles = [
        "d3d10core.dll",
        "d3d11.dll",
        "dxgi.dll",
        "winemetal.dll",
        "winemetal.so",
        "nvngx.dll"
    ]

    public static func ensureInstalled(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try HK4eResources.ensureDirs()

        let base = URL(string: "https://github.com/dawn-winery/dawn-signed/releases/download/dxmt-0.72/")!
        let needed = dxmtFiles

        let count = max(needed.count, 1)
        for (idx, name) in needed.enumerated() {
            let dst = HK4eResources.dxmtDir.appending(path: name)
            let url = base.appending(path: name)
            let per = progress.map { cb in
                return { frac in cb((Double(idx) + frac) / Double(count)) }
            }
            try await HK4eDownloader.downloadOnce(url: url, destination: dst, progress: per)
        }
        progress?(1)
    }

    public static func applyToPrefix(prefixURL: URL) throws {
        let system32 = prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard fm.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        for name in ["d3d10core.dll", "d3d11.dll", "dxgi.dll"] {
            let src = HK4eResources.dxmtDir.appending(path: name)
            let dst = system32.appending(path: name)
            let bak = system32.appending(path: name + ".bak")

            guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }

            if fm.fileExists(atPath: dst.path(percentEncoded: false)), !fm.fileExists(atPath: bak.path(percentEncoded: false)) {
                try? fm.moveItem(at: dst, to: bak)
            }
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                try? fm.removeItem(at: dst)
            }
            try? fm.copyItem(at: src, to: dst)
        }
    }

    public static func applyToRuntime(runtimeId: String) {
        let root = WineRuntimeManager.wineRoot(runtimeId: runtimeId)
        let winemetalDLLDst = root.appendingPathComponent("lib/wine/x86_64-windows/winemetal.dll", isDirectory: false)
        let winemetalSODst = root.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so", isDirectory: false)

        let winemetalDLLSrc = HK4eResources.dxmtDir.appending(path: "winemetal.dll")
        let winemetalSOSrc = HK4eResources.dxmtDir.appending(path: "winemetal.so")

        copyWithBackup(src: winemetalDLLSrc, dst: winemetalDLLDst)
        copyWithBackup(src: winemetalSOSrc, dst: winemetalSODst)
    }

    public static func revertRuntime(runtimeId: String) {
        let root = WineRuntimeManager.wineRoot(runtimeId: runtimeId)
        let targets = [
            root.appendingPathComponent("lib/wine/x86_64-windows/winemetal.dll", isDirectory: false),
            root.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so", isDirectory: false)
        ]
        for dst in targets {
            let bak = URL(fileURLWithPath: dst.path(percentEncoded: false) + ".bak")
            guard fm.fileExists(atPath: bak.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                try? fm.removeItem(at: dst)
            }
            try? fm.moveItem(at: bak, to: dst)
        }
    }

    private static func copyWithBackup(src: URL, dst: URL) {
        guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { return }
        guard fm.fileExists(atPath: dst.deletingLastPathComponent().path(percentEncoded: false)) else { return }

        let bak = URL(fileURLWithPath: dst.path(percentEncoded: false) + ".bak")
        if fm.fileExists(atPath: dst.path(percentEncoded: false)), !fm.fileExists(atPath: bak.path(percentEncoded: false)) {
            try? fm.moveItem(at: dst, to: bak)
        }
        if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
            try? fm.removeItem(at: dst)
        }
        try? fm.copyItem(at: src, to: dst)
    }

    public static func revertPrefix(prefixURL: URL) {
        let system32 = prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard fm.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        for name in ["d3d10core.dll", "d3d11.dll", "dxgi.dll"] {
            let dst = system32.appending(path: name)
            let bak = system32.appending(path: name + ".bak")
            guard fm.fileExists(atPath: bak.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                try? fm.removeItem(at: dst)
            }
            try? fm.moveItem(at: bak, to: dst)
        }
    }
}
