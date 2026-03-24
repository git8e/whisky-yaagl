//
//  HK4eGame.swift
//  WhiskyKit
//

import Foundation

public enum HK4eGame {
    public enum Region: String, Codable {
        case os
    }

    public struct Info: Codable {
        public var region: Region
        public var dataDirName: String
        public var executableName: String?
    }

    public static func detect(executableURL: URL) -> Info {
        let exeName = executableURL.lastPathComponent
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
