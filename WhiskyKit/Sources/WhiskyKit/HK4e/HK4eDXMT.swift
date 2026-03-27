//
//  HK4eDXMT.swift
//  WhiskyKit
//

import Foundation

public enum HK4eDXMT {
    private static var fm: FileManager { FileManager.default }

    private static let currentDXMTVersion = "0.74.0"
    private static let archiveName = "dxmt-v0.74-builtin-signed.tar.xz"
    private static let archiveURL = URL(
        string: "https://github.com/dawn-winery/dawn-signed/releases/download/dxmt-v0.74-builtin-signed/\(archiveName)"
    )!

    public static let dxmtFiles = [
        "d3d10core.dll",
        "d3d11.dll",
        "dxgi.dll",
        "winemetal.dll",
        "winemetal.so",
        "nvngx.dll"
    ]

    private static var versionFileURL: URL {
        HK4eResources.dxmtDir.appending(path: "installed-version.txt")
    }

    public static func installedVersion() -> String? {
        do {
            guard fm.fileExists(atPath: versionFileURL.path(percentEncoded: false)) else { return nil }
            return try String(contentsOf: versionFileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func isInstalledFilesPresent() -> Bool {
        dxmtFiles.allSatisfy { name in
            let url = HK4eResources.dxmtDir.appending(path: name)
            return fm.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    public static func useNativeDlls() -> Bool {
        // Mirror YAAGL behavior: DXMT 0.74+ is treated as "native" (system32 overrides).
        guard let v = installedVersion() else { return true }
        return compareVersions(v, currentDXMTVersion) >= 0
    }

    private static func compareVersions(_ a: String, _ b: String) -> Int {
        func parse(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0) ?? 0 }
        }
        let pa = parse(a)
        let pb = parse(b)
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va < vb ? -1 : 1 }
        }
        return 0
    }

    private static func clearDXMTDir() {
        let dir = HK4eResources.dxmtDir
        if fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try? fm.removeItem(at: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private static func markInstalled(version: String) {
        guard let data = version.data(using: .utf8) else { return }
        try? data.write(to: versionFileURL)
    }

    public static func ensureInstalled(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try HK4eResources.ensureDirs()

        if installedVersion() == currentDXMTVersion && isInstalledFilesPresent() {
            progress?(1)
            return
        }

        clearDXMTDir()

        let archiveLocalURL = HK4eResources.dxmtDir.appending(path: archiveName)
        try await HK4eDownloader.downloadOnce(url: archiveURL, destination: archiveLocalURL) { frac in
            progress?(min(max(frac * 0.9, 0.0), 0.9))
        }

        let base = "dxmt-v0.74-builtin-signed"
        let win = "\(base)/x86_64-windows"
        let unix = "\(base)/x86_64-unix"

        let winPaths = [
            "\(win)/d3d10core.dll",
            "\(win)/d3d11.dll",
            "\(win)/dxgi.dll",
            "\(win)/winemetal.dll",
            "\(win)/nvngx.dll"
        ]
        let unixPaths = [
            "\(unix)/winemetal.so"
        ]

        try Tar.extract(
            tarBall: archiveLocalURL,
            toURL: HK4eResources.dxmtDir,
            paths: winPaths + unixPaths,
            stripComponents: 2,
            useWildcards: false
        )

        try? fm.removeItem(at: archiveLocalURL)
        markInstalled(version: currentDXMTVersion)
        progress?(1)
    }

    public static func applyToPrefix(prefixURL: URL) throws {
        let system32 = prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard fm.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        // DXMT 0.74+ expects D3D DLLs in system32 with overrides.
        let names = useNativeDlls()
            ? ["d3d10core.dll", "d3d11.dll", "dxgi.dll"]
            : []

        // winemetal.dll is always copied to system32.
        for name in names + ["winemetal.dll"] {
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

        for name in ["d3d10core.dll", "d3d11.dll", "dxgi.dll", "winemetal.dll"] {
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
