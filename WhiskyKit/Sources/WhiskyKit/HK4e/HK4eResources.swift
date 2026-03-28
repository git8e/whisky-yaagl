//
//  HK4eResources.swift
//  WhiskyKit
//

import Foundation

public enum HK4eResources {
    private static var fm: FileManager { FileManager.default }

    public static var rootDir: URL {
        WhiskyPaths.applicationSupportRoot.appending(path: "HK4e", directoryHint: .isDirectory)
    }

    public static var dxmtDir: URL { rootDir.appending(path: "dxmt", directoryHint: .isDirectory) }
    public static var dxvkDir: URL { rootDir.appending(path: "dxvk", directoryHint: .isDirectory) }
    public static var reshadeDir: URL { rootDir.appending(path: "reshade", directoryHint: .isDirectory) }

    public static func ensureDirs() throws {
        for dir in [rootDir, dxmtDir, dxvkDir, reshadeDir] {
            if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
