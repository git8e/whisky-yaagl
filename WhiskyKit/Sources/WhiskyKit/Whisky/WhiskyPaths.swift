//
//  WhiskyPaths.swift
//  WhiskyKit
//
//  Centralizes on-disk storage locations for this fork.
//

import Foundation

public enum WhiskyPaths {
    public static let storageRootName = "Whisky"

    public static var applicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: storageRootName, directoryHint: .isDirectory)
    }

    public static var logsRoot: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: storageRootName, directoryHint: .isDirectory)
    }

    public static var legacyApplicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.whiskyBundleIdentifier, directoryHint: .isDirectory)
    }

    public static var legacyContainersRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Containers", directoryHint: .isDirectory)
            .appending(path: Bundle.whiskyBundleIdentifier, directoryHint: .isDirectory)
    }
}
