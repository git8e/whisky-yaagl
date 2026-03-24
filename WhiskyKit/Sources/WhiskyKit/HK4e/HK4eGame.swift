//
//  HK4eGame.swift
//  WhiskyKit
//

import Foundation

public enum HK4eGame {
    public enum Region: String, Codable {
        case os
        case cn
    }

    public struct Info: Codable {
        public var region: Region
        public var dataDirName: String
        public var executableName: String?
    }

    public static func detect(executableURL: URL) -> Info {
        let exeName = executableURL.lastPathComponent
        let gameDir = executableURL.deletingLastPathComponent()

        let lower = exeName.lowercased()
        if lower.contains("yuanshen") || FileManager.default.fileExists(atPath: gameDir.appendingPathComponent("YuanShen_Data").path) {
            return Info(region: .cn, dataDirName: "YuanShen_Data", executableName: exeName)
        }

        // Default to OS/global.
        return Info(region: .os, dataDirName: "GenshinImpact_Data", executableName: exeName)
    }

    public static func removedFiles(for info: Info) -> [String] {
        return [
            "\(info.dataDirName)/upload_crash.exe",
            "\(info.dataDirName)/Plugins/crashreport.exe",
            "\(info.dataDirName)/Plugins/vulkan-1.dll"
        ]
    }
}
