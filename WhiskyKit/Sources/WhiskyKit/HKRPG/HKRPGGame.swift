//
//  HKRPGGame.swift
//  WhiskyKit
//

import Foundation

public enum HKRPGGame {
    public enum Region: String, Codable, Equatable, Sendable {
        case os
        case cn
    }

    public static func registryKey(region: Region) -> String {
        // Mirrors YAAGL's fixWebview key selection.
        switch region {
        case .cn:
            return #"HKEY_CURRENT_USER\Software\miHoYo\崩坏：星穹铁道"#
        case .os:
            return #"HKEY_CURRENT_USER\Software\Cognosphere\Star Rail"#
        }
    }

    public static func removedFiles() -> [String] {
        // Mirrors YAAGL HKRPG_REMOVED.
        [
            "StarRail_Data/Plugins/x86_64/crashreport.exe",
            "StarRail_Data/Plugins/x86_64/vulkan-1.dll"
        ]
    }
}
