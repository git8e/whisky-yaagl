//
//  WhiskyPaths.swift
//  WhiskyKit
//
//  Centralizes on-disk storage locations for this fork.
//

import Foundation

public enum WhiskyPaths {
    public static let storageRootName = "whisky-yaagl"
    public static let legacyStorageRootName = "Whisky"
    public static let legacyBundleIdentifier = "com.isaacmarovitz.Whisky"

    private static let migrationLock = NSLock()
    nonisolated(unsafe) private static var didMigrateLegacyLayout = false

    private static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static var libraryDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    }

    public static var applicationSupportRoot: URL {
        migrateLegacyLayoutIfNeeded()
        return applicationSupportDirectory
            .appending(path: storageRootName, directoryHint: .isDirectory)
    }

    public static var logsRoot: URL {
        migrateLegacyLayoutIfNeeded()
        return libraryDirectory
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: storageRootName, directoryHint: .isDirectory)
    }

    public static var legacyApplicationSupportRoot: URL {
        applicationSupportDirectory
            .appending(path: legacyStorageRootName, directoryHint: .isDirectory)
    }

    public static var legacyBundleApplicationSupportRoot: URL {
        applicationSupportDirectory
            .appending(path: legacyBundleIdentifier, directoryHint: .isDirectory)
    }

    public static var legacyLogsRoot: URL {
        libraryDirectory
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: legacyStorageRootName, directoryHint: .isDirectory)
    }

    public static var legacyContainersRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Containers", directoryHint: .isDirectory)
            .appending(path: legacyBundleIdentifier, directoryHint: .isDirectory)
    }

    public static func migrateLegacyLayoutIfNeeded() {
        migrationLock.lock()
        defer { migrationLock.unlock() }

        guard !didMigrateLegacyLayout else { return }
        didMigrateLegacyLayout = true

        let targetSupportRoot = applicationSupportDirectory
            .appending(path: storageRootName, directoryHint: .isDirectory)
        let targetLogsRoot = libraryDirectory
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: storageRootName, directoryHint: .isDirectory)

        mergeDirectoryIfNeeded(from: legacyApplicationSupportRoot, to: targetSupportRoot)
        mergeDirectoryIfNeeded(from: legacyBundleApplicationSupportRoot, to: targetSupportRoot)
        mergeDirectoryIfNeeded(from: legacyLogsRoot, to: targetLogsRoot)
    }

    private static func mergeDirectoryIfNeeded(from legacyRoot: URL, to targetRoot: URL) {
        let fm = FileManager.default

        guard fm.fileExists(atPath: legacyRoot.path(percentEncoded: false)) else { return }

        do {
            try fm.createDirectory(at: targetRoot.deletingLastPathComponent(), withIntermediateDirectories: true)

            if !fm.fileExists(atPath: targetRoot.path(percentEncoded: false)) {
                try fm.moveItem(at: legacyRoot, to: targetRoot)
                return
            }

            let entries = try fm.contentsOfDirectory(at: legacyRoot, includingPropertiesForKeys: nil)
            for entry in entries {
                let destination = targetRoot.appending(path: entry.lastPathComponent, directoryHint: entry.hasDirectoryPath ? .isDirectory : .notDirectory)
                guard !fm.fileExists(atPath: destination.path(percentEncoded: false)) else { continue }

                do {
                    try fm.moveItem(at: entry, to: destination)
                } catch {
                    try? FileCopy.copyItem(at: entry, to: destination)
                }
            }
        } catch {
            return
        }
    }
}
