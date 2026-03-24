//
//  HK4ePatchState.swift
//  WhiskyKit
//

import Foundation

struct HK4ePatchState: Codable {
    var patched: Bool
    var gameDir: String
    var executablePath: String

    var removeCrashFiles: Bool
    var dxmt: Bool
    var dxvk: Bool
    var reshade: Bool
    var hdr: Bool
    var resolution: Bool
}
