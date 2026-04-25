//
//  HKRPGJadeite.swift
//  WhiskyKit
//

import Foundation

public enum HKRPGJadeite {
    private static var fm: FileManager { FileManager.default }

    private static let currentVersion = "4.1.0"
    private static let zipURL = URL(string: "https://codeberg.org/mkrsym1/jadeite/releases/download/v4.1.0/v4.1.0.zip")!

    private static func workDir(bottle: Bottle) throws -> URL {
        let dir = bottle.url.appendingPathComponent("HKRPG", isDirectory: true)
        if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func extractZip(zipURL: URL, to destinationDir: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zipURL.path(percentEncoded: false), destinationDir.path(percentEncoded: false)]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw HKRPGJadeiteError.extractFailed
        }
    }

    private static func findJadeiteExe(in root: URL) -> URL? {
        guard let it = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in it {
            if url.lastPathComponent.lowercased() == "jadeite.exe" {
                return url
            }
        }
        return nil
    }

    private static func installedVersion(in destDir: URL) -> String? {
        let v = destDir.appendingPathComponent("installed-version.txt", isDirectory: false)
        guard fm.fileExists(atPath: v.path(percentEncoded: false)) else { return nil }
        return (try? String(contentsOf: v, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func ensureInstalled(bottle: Bottle, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let destDir = bottle.url
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("jadeite", isDirectory: true)

        let exe = destDir.appendingPathComponent("jadeite.exe", isDirectory: false)
        if installedVersion(in: destDir) == currentVersion,
           fm.fileExists(atPath: exe.path(percentEncoded: false)) {
            progress?(1)
            return
        }

        let dir = try workDir(bottle: bottle)
        let zipLocal = dir.appendingPathComponent("jadeite_\(currentVersion).zip", isDirectory: false)
        let extractDir = dir.appendingPathComponent("jadeite_extract", isDirectory: true)

        if fm.fileExists(atPath: zipLocal.path(percentEncoded: false)) {
            try? fm.removeItem(at: zipLocal)
        }
        if fm.fileExists(atPath: extractDir.path(percentEncoded: false)) {
            try? fm.removeItem(at: extractDir)
        }
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        try await RemoteDownloader.downloadOnce(url: zipURL, destination: zipLocal) { frac in
            progress?(min(max(frac * 0.7, 0.0), 0.7))
        }

        try extractZip(zipURL: zipLocal, to: extractDir)
        progress?(0.85)

        guard let foundExe = findJadeiteExe(in: extractDir) else {
            throw HKRPGJadeiteError.jadeiteNotFound
        }
        let srcDir = foundExe.deletingLastPathComponent()

        try FileCopy.copyItem(at: srcDir, to: destDir, replacing: true)
        try (currentVersion + "\n").write(
            to: destDir.appendingPathComponent("installed-version.txt", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        try? fm.removeItem(at: zipLocal)
        try? fm.removeItem(at: extractDir)
        progress?(1)
    }
}

public enum HKRPGJadeiteError: LocalizedError {
    case extractFailed
    case jadeiteNotFound

    public var errorDescription: String? {
        switch self {
        case .extractFailed:
            return String(localized: "error.extractJadeiteZip")
        case .jadeiteNotFound:
            return String(localized: "error.jadeiteNotFound")
        }
    }
}
