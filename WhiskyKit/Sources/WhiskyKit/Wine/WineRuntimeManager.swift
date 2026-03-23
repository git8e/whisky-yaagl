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

public enum WineRuntimeManager {
    private static var fm: FileManager { FileManager.default }

    private static var versionsFolder: URL {
        WhiskyWineInstaller.libraryFolder.appending(path: "WineVersions", directoryHint: .isDirectory)
    }

    public static func wineRoot(runtimeId: String) -> URL {
        if runtimeId == WineRuntimes.whiskyDefaultId {
            return WhiskyWineInstaller.libraryFolder.appending(path: "Wine", directoryHint: .isDirectory)
        }
        return versionsFolder.appending(path: runtimeId, directoryHint: .isDirectory)
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
            // WhiskyWine is managed by the regular setup flow.
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
        let archive = try await downloadOnce(runtimeId: runtimeId, url: remoteURL, progress: progress)
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

        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let task = session.downloadTask(with: url)
        return try await withCheckedThrowingContinuation { cont in
            delegate.continuation = cont
            task.resume()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let destination: URL
        let progress: (@Sendable (Double) -> Void)?
        var continuation: CheckedContinuation<URL, Error>?

        init(destination: URL, progress: (@Sendable (Double) -> Void)?) {
            self.destination = destination
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let frac = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progress?(min(max(frac, 0.0), 1.0))
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            do {
                if WineRuntimeManager.fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                    continuation?.resume(returning: destination)
                    continuation = nil
                    return
                }
                try WineRuntimeManager.fm.moveItem(at: location, to: destination)
                continuation?.resume(returning: destination)
                continuation = nil
            } catch {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            continuation?.resume(throwing: error)
            continuation = nil
        }
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
            try fm.copyItem(at: entry, to: target)
        }
    }

    private static func locateWineRoot(in root: URL) -> URL? {
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

    public var errorDescription: String? {
        switch self {
        case .whiskyWineMissing:
            return "WhiskyWine is not installed. Please complete the setup first."
        case .unknownRuntime(let id):
            return "Unknown Wine runtime: \(id)"
        case .missingRemoteURL(let id):
            return "Wine runtime has no download URL: \(id)"
        case .invalidArchive(let message):
            return "Invalid Wine archive: \(message)"
        }
    }
}
