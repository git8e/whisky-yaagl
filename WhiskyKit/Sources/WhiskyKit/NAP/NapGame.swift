//
//  NapGame.swift
//  WhiskyKit
//

import Foundation

public enum NapGame {
    public enum Region: String, CaseIterable, Codable, Sendable {
        case os
        case cn
    }

    public static func registryKey(region: Region) -> String {
        switch region {
        case .cn:
            return "HKEY_CURRENT_USER\\Software\\miHoYo\\\u{7EDD}\u{533A}\u{96F6}"
        case .os:
            return "HKEY_CURRENT_USER\\Software\\miHoYo\\ZenlessZoneZero"
        }
    }

    public static func dataDirName(executableURL: URL) -> String {
        executableURL.deletingPathExtension().lastPathComponent + "_Data"
    }

    public static func removedFiles(executableURL: URL) -> [String] {
        // Mirrors YAAGL `NAP_REMOVED`.
        let dataDir = dataDirName(executableURL: executableURL)
        return ["\(dataDir)/Plugins/x86_64/vulkan-1.dll"]
    }
}
