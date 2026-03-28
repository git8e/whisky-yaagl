//
//  HK4eDXVK.swift
//  WhiskyKit
//

import Foundation

public enum HK4eDXVK {
    private static var fm: FileManager { FileManager.default }

    public static let dxvkFiles = [
        "d3d9.dll",
        "d3d10core.dll",
        "d3d11.dll",
        "dxgi.dll"
    ]

    public static func ensureInstalled(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        try HK4eResources.ensureDirs()

        let base = URL(string: "https://github.com/3Shain/winecx/releases/download/gi-wine-1.0/")!
        let needed = dxvkFiles
        let count = max(needed.count, 1)
        for (idx, name) in needed.enumerated() {
            let dst = HK4eResources.dxvkDir.appending(path: name)
            let url = base.appending(path: name)
            var per: (@Sendable (Double) -> Void)?
            if let cb = progress {
                per = { frac in
                    cb((Double(idx) + frac) / Double(count))
                }
            }
            try await RemoteDownloader.downloadOnce(url: url, destination: dst, progress: per)
        }
        progress?(1)
    }

    public static func applyToPrefix(prefixURL: URL) throws {
        let system32 = prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard fm.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        for name in dxvkFiles {
            let src = HK4eResources.dxvkDir.appending(path: name)
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

    public static func revertPrefix(prefixURL: URL) {
        let system32 = prefixURL.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard fm.fileExists(atPath: system32.path(percentEncoded: false)) else { return }

        for name in dxvkFiles {
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
