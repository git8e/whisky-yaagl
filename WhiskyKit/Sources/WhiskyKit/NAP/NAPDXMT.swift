//
//  NAPDXMT.swift
//  WhiskyKit
//

import Foundation

public enum NAPDXMT {
    private static var fm: FileManager { FileManager.default }

    private static let currentDXMTVersion = "0.74.0"
    private static let archiveName = "dxmt-v0.74-builtin-signed.tar.xz"
    private static let archiveURL = URL(
        string: "https://github.com/dawn-winery/dawn-signed/releases/download/dxmt-v0.74-builtin-signed/\(archiveName)"
    )!

    // Mirrors YAAGL DXMT_FILES + winemetal (NAP does not copy nvngx.dll).
    public static let dxmtFiles = [
        "d3d10core.dll",
        "d3d11.dll",
        "dxgi.dll",
        "winemetal.dll",
        "winemetal.so"
    ]

    private static var versionFileURL: URL {
        NAPResources.dxmtDir.appending(path: "installed-version.txt")
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
            let url = NAPResources.dxmtDir.appending(path: name)
            return fm.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    public static func useNativeDlls() -> Bool {
        // Mirror YAAGL behavior: DXMT 0.74+ is treated as "native" (runtime builtins).
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
        let dir = NAPResources.dxmtDir
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
        try NAPResources.ensureDirs()

        if installedVersion() == currentDXMTVersion && isInstalledFilesPresent() {
            progress?(1)
            return
        }

        clearDXMTDir()

        let archiveLocalURL = NAPResources.dxmtDir.appending(path: archiveName)
        try await RemoteDownloader.downloadOnce(url: archiveURL, destination: archiveLocalURL) { frac in
            progress?(min(max(frac * 0.9, 0.0), 0.9))
        }

        let base = "dxmt-v0.74-builtin-signed"
        let win = "\(base)/x86_64-windows"
        let unix = "\(base)/x86_64-unix"

        let winPaths = [
            "\(win)/d3d10core.dll",
            "\(win)/d3d11.dll",
            "\(win)/dxgi.dll",
            "\(win)/winemetal.dll"
        ]
        let unixPaths = [
            "\(unix)/winemetal.so"
        ]

        try Tar.extract(
            tarBall: archiveLocalURL,
            toURL: NAPResources.dxmtDir,
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

        if useNativeDlls() {
            restoreBackups(in: system32, names: ["d3d10core.dll", "d3d11.dll", "dxgi.dll"])
        }

        let names = useNativeDlls() ? [] : ["d3d10core.dll", "d3d11.dll", "dxgi.dll"]
        for name in names + ["winemetal.dll"] {
            let src = NAPResources.dxmtDir.appending(path: name)
            let dst = system32.appending(path: name)
            let bak = system32.appending(path: name + ".bak")
            guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }

            if fm.fileExists(atPath: dst.path(percentEncoded: false)), !fm.fileExists(atPath: bak.path(percentEncoded: false)) {
                try? fm.moveItem(at: dst, to: bak)
            }
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                try? fm.removeItem(at: dst)
            }
            try? FileCopy.copyItem(at: src, to: dst, replacing: true)
        }
    }

    private static func restoreBackups(in system32: URL, names: [String]) {
        for name in names {
            let dst = system32.appending(path: name)
            let bak = system32.appending(path: name + ".bak")
            guard fm.fileExists(atPath: bak.path(percentEncoded: false)) else { continue }
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                try? fm.removeItem(at: dst)
            }
            try? fm.moveItem(at: bak, to: dst)
        }
    }

    public static func applyToRuntime(runtimeRoot: URL) {
        let builtinDir = runtimeRoot.appendingPathComponent("lib/wine/x86_64-windows", isDirectory: true)

        if useNativeDlls(), fm.fileExists(atPath: builtinDir.path(percentEncoded: false)) {
            for name in ["d3d10core.dll", "d3d11.dll", "dxgi.dll"] {
                let src = NAPResources.dxmtDir.appending(path: name)
                let dst = builtinDir.appending(path: name)
                copyWithBackup(src: src, dst: dst)
            }
        }

        let winemetalDLLDst = runtimeRoot.appendingPathComponent("lib/wine/x86_64-windows/winemetal.dll", isDirectory: false)
        let winemetalSODst = runtimeRoot.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so", isDirectory: false)

        let winemetalDLLSrc = NAPResources.dxmtDir.appending(path: "winemetal.dll")
        let winemetalSOSrc = NAPResources.dxmtDir.appending(path: "winemetal.so")

        copyWithBackup(src: winemetalDLLSrc, dst: winemetalDLLDst)
        copyWithBackup(src: winemetalSOSrc, dst: winemetalSODst)
    }

    public static func revertRuntime(runtimeRoot: URL) {
        let targets = [
            runtimeRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d10core.dll", isDirectory: false),
            runtimeRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll", isDirectory: false),
            runtimeRoot.appendingPathComponent("lib/wine/x86_64-windows/dxgi.dll", isDirectory: false),
            runtimeRoot.appendingPathComponent("lib/wine/x86_64-windows/winemetal.dll", isDirectory: false),
            runtimeRoot.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so", isDirectory: false)
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
        try? FileCopy.copyItem(at: src, to: dst, replacing: true)
    }
}
