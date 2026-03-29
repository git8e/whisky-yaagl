//
//  HKRPGResources.swift
//  WhiskyKit
//

import Foundation

public enum HKRPGResources {
    private static var fm: FileManager { FileManager.default }

    public static var rootDir: URL {
        // Store reusable HKRPG assets under Libraries/ so they're grouped with other shared components.
        WhiskyWineInstaller.libraryFolder.appending(path: "HKRPG", directoryHint: .isDirectory)
    }

    public static var dxmtDir: URL { rootDir.appending(path: "dxmt", directoryHint: .isDirectory) }

    public static func ensureDirs() throws {
        for dir in [rootDir, dxmtDir] {
            if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
