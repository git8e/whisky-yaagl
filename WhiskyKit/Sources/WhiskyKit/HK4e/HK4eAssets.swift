//
//  HK4eAssets.swift
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

public enum HK4eAssets {
    private static let fm = FileManager.default

    public static func runtimeRootURL() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["HK4E_RUNTIME_ROOT"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            if fm.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        }

        if let res = Bundle.main.resourceURL {
            let bundled = res.appending(path: "HK4eRuntime", directoryHint: .isDirectory)
            if fm.fileExists(atPath: bundled.path(percentEncoded: false)) { return bundled }
        }

        throw HK4eAssetsError.runtimeMissing
    }

    public static func protonExtrasDir() throws -> URL {
        let root = try runtimeRootURL()

        let direct = root.appending(path: "protonextras", directoryHint: .isDirectory)
        if fm.fileExists(atPath: direct.path(percentEncoded: false)) { return direct }

        let yaagl = root
            .appending(path: "sidecar", directoryHint: .isDirectory)
            .appending(path: "protonextras", directoryHint: .isDirectory)
        if fm.fileExists(atPath: yaagl.path(percentEncoded: false)) { return yaagl }

        throw HK4eAssetsError.protonExtrasMissing
    }
}

public enum HK4eAssetsError: LocalizedError {
    case runtimeMissing
    case protonExtrasMissing

    public var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            return "HK4e runtime not found. Set HK4E_RUNTIME_ROOT or bundle Resources/HK4eRuntime."
        case .protonExtrasMissing:
            return "HK4e runtime missing protonextras (expected protonextras/ or sidecar/protonextras/)."
        }
    }
}
