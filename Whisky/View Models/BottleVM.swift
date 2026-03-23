//
//  BottleVM.swift
//  Whisky
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
import SemanticVersion
import WhiskyKit

// swiftlint:disable:next todo
// TODO: Don't use unchecked!
final class BottleVM: ObservableObject, @unchecked Sendable {
    @MainActor static let shared = BottleVM()

    var bottlesList = BottleData()
    @Published var bottles: [Bottle] = []

    @MainActor
    func loadBottles() {
        bottles = bottlesList.loadBottles()
    }

    func countActive() -> Int {
        return bottles.filter { $0.isAvailable == true }.count
    }

    func createNewBottle(
        bottleName: String,
        winVersion: WinVersion,
        bottleURL: URL,
        wineRuntimeId: String,
        wineArchiveURL: URL? = nil,
        initialMetalHud: Bool = false,
        initialRetinaMode: Bool = false,
        initialSteamPatch: Bool = false,
        initialCustomResolutionEnabled: Bool = false,
        initialCustomResolutionWidth: Int = 1920,
        initialCustomResolutionHeight: Int = 1080,
        pinProgramURL: URL? = nil
    ) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task.detached {
            var bottleId: Bottle?
            do {
                try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle

                await MainActor.run {
                    self.bottles.append(bottle)
                }

                bottle.settings.wineRuntimeId = wineRuntimeId
                try await WineRuntimeManager.ensureInstalled(runtimeId: wineRuntimeId, localArchive: wineArchiveURL)

                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName

                bottle.settings.metalHud = initialMetalHud

                bottle.settings.hk4eSteamPatch = initialSteamPatch
                bottle.settings.hk4eCustomResolutionEnabled = initialCustomResolutionEnabled
                bottle.settings.hk4eCustomResolutionWidth = initialCustomResolutionWidth
                bottle.settings.hk4eCustomResolutionHeight = initialCustomResolutionHeight

                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion(bottle: bottle)
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

                if initialRetinaMode {
                    try await Wine.changeRetinaMode(bottle: bottle, retinaMode: true)
                }

                if initialSteamPatch {
                    try SteamPatch.apply(prefixURL: bottle.url)
                }

                if initialCustomResolutionEnabled {
                    try await HK4eResolution.apply(
                        bottle: bottle,
                        width: initialCustomResolutionWidth,
                        height: initialCustomResolutionHeight
                    )
                }

                if let pinProgramURL {
                    bottle.settings.pins.append(
                        PinnedProgram(name: pinProgramURL.deletingPathExtension().lastPathComponent, url: pinProgramURL)
                    )
                    bottle.settings.hk4eGameExecutableURL = pinProgramURL
                }

                // Add record
                await MainActor.run {
                    self.bottlesList.paths.append(newBottleDir)
                    self.loadBottles()
                }
            } catch {
                print("Failed to create new bottle: \(error)")
                if let bottle = bottleId {
                    await MainActor.run {
                        if let index = self.bottles.firstIndex(of: bottle) {
                            self.bottles.remove(at: index)
                        }
                    }
                }
            }
        }
        return newBottleDir
    }
}
