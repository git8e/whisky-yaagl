//
//  WineRuntimeManager.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import CryptoKit

public enum WineRuntimeManager {
    private static var fm: FileManager { FileManager.default }

    // Per-bottle isolated runtime folder name (stored inside the bottle directory).
    public static let isolatedRuntimeFolderName = "WineRuntime"
    private static let isolatedRuntimeMarkerFileName = ".base-runtime-id"

    private static var versionsFolder: URL {
        WhiskyWineInstaller.libraryFolder.appending(path: "WineVersions", directoryHint: .isDirectory)
    }

    public static func wineRoot(runtimeId: String) -> URL {
        if runtimeId == WineRuntimes.whiskyDefaultId {
            return WhiskyWineInstaller.libraryFolder.appending(path: "Wine", directoryHint: .isDirectory)
        }
        return versionsFolder.appending(path: runtimeId, directoryHint: .isDirectory)
    }

    public static func isolatedRuntimeRoot(bottleURL: URL) -> URL {
        bottleURL.appendingPathComponent(isolatedRuntimeFolderName, isDirectory: true)
    }

    public static func effectiveWineRoot(bottle: Bottle) -> URL {
        let isolated = isolatedRuntimeRoot(bottleURL: bottle.url)
        let wine64 = isolated.appendingPathComponent("bin/wine64", isDirectory: false)
        let wine = isolated.appendingPathComponent("bin/wine", isDirectory: false)
        if fm.fileExists(atPath: wine64.path(percentEncoded: false)) || fm.fileExists(atPath: wine.path(percentEncoded: false)) {
            return isolated
        }
        return wineRoot(runtimeId: bottle.settings.wineRuntimeId)
    }

    public static func binFolder(bottle: Bottle) -> URL {
        effectiveWineRoot(bottle: bottle).appending(path: "bin", directoryHint: .isDirectory)
    }

    public static func wineBinary(bottle: Bottle) -> URL {
        let bin = binFolder(bottle: bottle)
        let wine64 = bin.appending(path: "wine64")
        if fm.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return bin.appending(path: "wine")
    }

    public static func wineserverBinary(bottle: Bottle) -> URL {
        return binFolder(bottle: bottle).appending(path: "wineserver")
    }

    public static func ensureIsolatedRuntime(
        bottle: Bottle,
        baseRuntimeId: String,
        status: (@Sendable (String) -> Void)? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Make sure the base runtime exists.
        try await ensureInstalled(runtimeId: baseRuntimeId, status: status, progress: progress)

        let src = wineRoot(runtimeId: baseRuntimeId)
        let dst = isolatedRuntimeRoot(bottleURL: bottle.url)
        let marker = dst.appendingPathComponent(isolatedRuntimeMarkerFileName, isDirectory: false)

        let dstWine64 = dst.appendingPathComponent("bin/wine64", isDirectory: false)
        let dstWine = dst.appendingPathComponent("bin/wine", isDirectory: false)

        if fm.fileExists(atPath: marker.path(percentEncoded: false)),
           let current = try? String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           current == baseRuntimeId,
           (fm.fileExists(atPath: dstWine64.path(percentEncoded: false)) || fm.fileExists(atPath: dstWine.path(percentEncoded: false))) {
            return
        }

        status?("Preparing isolated Wine runtime")
        if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
            try? fm.removeItem(at: dst)
        }

        try FileCopy.copyItem(at: src, to: dst)
        try (baseRuntimeId + "\n").write(to: marker, atomically: true, encoding: .utf8)
        removeQuarantineRecursively(path: dst.path(percentEncoded: false))
    }

    public static func binFolder(runtimeId: String) -> URL {
        return wineRoot(runtimeId: runtimeId).appending(path: "bin", directoryHint: .isDirectory)
    }

    public static func wineBinary(runtimeId: String) -> URL {
        let bin = binFolder(runtimeId: runtimeId)
        let wine64 = bin.appending(path: "wine64")
        if fm.fileExists(atPath: wine64.path(percentEncoded: false)) {
            return wine64
        }
        return bin.appending(path: "wine")
    }

    public static func wineserverBinary(runtimeId: String) -> URL {
        return binFolder(runtimeId: runtimeId).appending(path: "wineserver")
    }

    public static func isInstalled(runtimeId: String) -> Bool {
        return fm.fileExists(atPath: wineBinary(runtimeId: runtimeId).path(percentEncoded: false))
    }

    public static func ensureInstalled(
        runtimeId: String,
        localArchive: URL? = nil,
        status: (@Sendable (String) -> Void)? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if runtimeId == WineRuntimes.whiskyDefaultId {
            guard let runtime = WineRuntimes.runtime(id: runtimeId),
                  let remoteURL = runtime.remoteURL else {
                throw WineRuntimeManagerError.missingRemoteURL(runtimeId)
            }

            if isInstalled(runtimeId: runtimeId) {
                return
            }

            status?("Downloading WhiskyWine")
            var archive = try await downloadOnce(
                runtimeId: runtimeId,
                url: remoteURL,
                progress: progress
            )

            do {
                try await verifyArchiveIfNeeded(runtime: runtime, archiveURL: archive)
            } catch let error as WineRuntimeManagerError {
                if case .integrityCheckFailed = error {
                    // Auto self-heal: delete and re-download once.
                    archive = try await downloadOnce(runtimeId: runtimeId, url: remoteURL, progress: progress)
                    try await verifyArchiveIfNeeded(runtime: runtime, archiveURL: archive)
                } else {
                    throw error
                }
            }

            status?("Installing WhiskyWine")
            let tempCopy = WhiskyWineInstaller.applicationFolder
                .appending(path: "Temp", directoryHint: .isDirectory)
                .appending(path: "WhiskyWineInstall-\(UUID().uuidString).tar.gz")
            if !fm.fileExists(atPath: tempCopy.deletingLastPathComponent().path(percentEncoded: false)) {
                try? fm.createDirectory(at: tempCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: tempCopy.path(percentEncoded: false)) {
                try? fm.removeItem(at: tempCopy)
            }
            try FileCopy.copyItem(at: archive, to: tempCopy, replacing: true)
            WhiskyWineInstaller.install(from: tempCopy)

            removeQuarantineRecursively(path: wineRoot(runtimeId: runtimeId).path(percentEncoded: false))

            guard isInstalled(runtimeId: runtimeId) else {
                throw WineRuntimeManagerError.whiskyWineMissing
            }
            return
        }

        if isInstalled(runtimeId: runtimeId) {
            return
        }

        guard let runtime = WineRuntimes.runtime(id: runtimeId) else {
            throw WineRuntimeManagerError.unknownRuntime(runtimeId)
        }

        if let localArchive {
            status?("Installing Wine from local archive")
            try install(runtime: runtime, fromArchive: localArchive)
            return
        }

        guard let remoteURL = runtime.remoteURL else {
            throw WineRuntimeManagerError.missingRemoteURL(runtimeId)
        }

        status?("Downloading Wine runtime")
        var archive = try await downloadOnce(runtimeId: runtimeId, url: remoteURL, progress: progress)
        do {
            try await verifyArchiveIfNeeded(runtime: runtime, archiveURL: archive)
        } catch let error as WineRuntimeManagerError {
            if case .integrityCheckFailed = error {
                archive = try await downloadOnce(runtimeId: runtimeId, url: remoteURL, progress: progress)
                try await verifyArchiveIfNeeded(runtime: runtime, archiveURL: archive)
            } else {
                throw error
            }
        }
        status?("Installing Wine runtime")
        try install(runtime: runtime, fromArchive: archive)
    }

    private static func downloadsFolder() throws -> URL {
        let url = WhiskyWineInstaller.applicationFolder.appending(path: "Downloads", directoryHint: .isDirectory)
        if !fm.fileExists(atPath: url.path(percentEncoded: false)) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static func downloadOnce(
        runtimeId: String,
        url: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let downloads = try downloadsFolder()
        let fileName = (url.lastPathComponent.isEmpty ? "wine-\(runtimeId).tar" : url.lastPathComponent)
        let destination = downloads.appending(path: "\(runtimeId)-\(fileName)")

        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }

        do {
            try await RemoteDownloader.downloadOnce(url: url, destination: destination, progress: progress)
        } catch let error as RemoteDownloader.DownloadError {
            if case .cancelled = error.kind {
                throw CancellationError()
            }
            throw error
        }
        return destination
    }

    private static func verifyArchiveIfNeeded(runtime: WineRuntime, archiveURL: URL) async throws {
        guard let expected = runtime.sha256?.trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty else {
            return
        }

        let normalizedExpected = expected.lowercased()

        // Compute hash on a background thread.
        let computed = try await Task.detached(priority: .utility) {
            try computeSHA256(url: archiveURL)
        }.value
        try Task.checkCancellation()

        if computed.lowercased() == normalizedExpected {
            return
        }

        // Corrupted / partial download: delete and re-download.
        try? fm.removeItem(at: archiveURL)
        throw WineRuntimeManagerError.integrityCheckFailed
    }

    private static func computeSHA256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func install(runtime: WineRuntime, fromArchive archiveURL: URL) throws {
        let runtimeId = runtime.id
        let destination = wineRoot(runtimeId: runtimeId)

        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fm.removeItem(at: destination)
        }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let tempDir = WhiskyWineInstaller.applicationFolder
            .appending(path: "Temp", directoryHint: .isDirectory)
            .appending(path: "WineInstall-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        try Tar.untar(tarBall: archiveURL, toURL: tempDir)

        let wineRootInArchive: URL
        if let path = runtime.archive.winePathInArchive {
            wineRootInArchive = tempDir.appendingPathComponent(path, isDirectory: true)
        } else if let located = locateWineRoot(in: tempDir) {
            wineRootInArchive = located
        } else {
            throw WineRuntimeManagerError.invalidArchive("Cannot locate wine folder in archive")
        }

        try copyContents(from: wineRootInArchive, to: destination)

        removeQuarantineRecursively(path: destination.path(percentEncoded: false))

        guard isInstalled(runtimeId: runtimeId) else {
            throw WineRuntimeManagerError.invalidArchive("Installed runtime is missing wine64")
        }
    }

    private static func removeQuarantineRecursively(path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-dr", "com.apple.quarantine", path]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // best-effort
        }
    }

    private static func copyContents(from sourceDir: URL, to destDir: URL) throws {
        let entries = try fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        for entry in entries {
            let target = destDir.appendingPathComponent(entry.lastPathComponent, isDirectory: entry.hasDirectoryPath)
            if fm.fileExists(atPath: target.path(percentEncoded: false)) {
                try fm.removeItem(at: target)
            }
            try FileCopy.copyItem(at: entry, to: target, replacing: true)
        }
    }

    private static func locateWineRoot(in root: URL) -> URL? {
        // Some archives are "flat" and extract directly into the root (bin/, lib/, share/...).
        // In that case the wine root is `root` itself, and the directory enumerator below
        // will never consider `root` (only its children).
        let rootBin = root.appending(path: "bin", directoryHint: .isDirectory)
        let rootWine64 = rootBin.appending(path: "wine64")
        let rootWine = rootBin.appending(path: "wine")
        if fm.fileExists(atPath: rootWine64.path(percentEncoded: false)) || fm.fileExists(atPath: rootWine.path(percentEncoded: false)) {
            return root
        }

        // Look for a directory that contains bin/wine64 or bin/wine
        let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.hasDirectoryPath {
                let bin = url.appending(path: "bin", directoryHint: .isDirectory)
                let wine64 = bin.appending(path: "wine64")
                let wine = bin.appending(path: "wine")
                if fm.fileExists(atPath: wine64.path(percentEncoded: false)) || fm.fileExists(atPath: wine.path(percentEncoded: false)) {
                    return url
                }
            }
        }

        return nil
    }
}

public enum WineRuntimeManagerError: LocalizedError {
    case whiskyWineMissing
    case unknownRuntime(String)
    case missingRemoteURL(String)
    case invalidArchive(String)
    case integrityCheckFailed

    public var errorDescription: String? {
        switch self {
        case .whiskyWineMissing:
            return String(localized: "runtime.error.whiskyWineMissing")
        case .unknownRuntime(let id):
            return String(format: String(localized: "runtime.error.unknownRuntime"), id)
        case .missingRemoteURL(let id):
            return String(format: String(localized: "runtime.error.missingRemoteURL"), id)
        case .invalidArchive(let message):
            return String(format: String(localized: "runtime.error.invalidArchive"), message)
        case .integrityCheckFailed:
            return String(localized: "runtime.error.integrityFailed")
        }
    }
}
