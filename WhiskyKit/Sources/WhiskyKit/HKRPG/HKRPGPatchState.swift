//
//  HKRPGPatchState.swift
//  WhiskyKit
//

import Foundation

public struct HKRPGPatchState: Codable, Equatable {
    var patched: Bool
    var gameDir: String
    var executablePath: String
    var removedFiles: Bool
}
