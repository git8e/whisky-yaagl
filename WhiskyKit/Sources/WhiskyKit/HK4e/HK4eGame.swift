//
//  HK4eGame.swift
//  WhiskyKit
//

import Foundation

public enum HK4eGame {
    public enum Region: String, Codable, CaseIterable {
        case os
        case cn
    }

    public struct Info: Codable {
        public var region: Region
        public var dataDirName: String
        public var executableName: String?
    }

    public static func resolveRegion(executableName: String, fallback: Region) -> Region {
        let lower = executableName.lowercased()
        if lower.contains("yuanshen") {
            return .cn
        }
        if lower.contains("genshinimpact") {
            return .os
        }
        return fallback
    }

    public static func detect(bottle: Bottle, executableURL: URL) -> Info {
        let exeName = executableURL.lastPathComponent
        let region = resolveRegion(executableName: exeName, fallback: bottle.settings.hk4eRegion)
        let dataDirName = (region == .cn) ? "YuanShen_Data" : "GenshinImpact_Data"
        return Info(region: region, dataDirName: dataDirName, executableName: exeName)
    }

    public static func removedFiles(for info: Info) -> [String] {
        return [
            "\(info.dataDirName)/upload_crash.exe",
            "\(info.dataDirName)/Plugins/crashreport.exe",
            "\(info.dataDirName)/Plugins/vulkan-1.dll"
        ]
    }
}
