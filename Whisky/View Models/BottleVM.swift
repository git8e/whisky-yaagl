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

    @Published var isCreatingBottle: Bool = false
    @Published var createBottleStatus: String = ""
    @Published var createBottleProgress: Double? = nil
    @Published var createBottleErrorMessage: String? = nil
    @Published var createdBottleURL: URL? = nil

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

        Task { @MainActor in
            self.isCreatingBottle = true
            self.createBottleStatus = "Preparing bottle"
            self.createBottleProgress = nil
            self.createBottleErrorMessage = nil
            self.createdBottleURL = nil
        }

        Task.detached {
            var bottleId: Bottle?
            do {
                await MainActor.run {
                    self.createBottleStatus = "Creating bottle directory"
                }
                try FileManager.default.createDirectory(atPath: newBottleDir.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: newBottleDir, inFlight: true)
                bottleId = bottle

                await MainActor.run {
                    self.bottles.append(bottle)
                }

                bottle.settings.wineRuntimeId = wineRuntimeId
                try await WineRuntimeManager.ensureInstalled(
                    runtimeId: wineRuntimeId,
                    localArchive: wineArchiveURL,
                    status: { message in
                        Task { @MainActor in
                            self.createBottleStatus = message
                            if message.lowercased().contains("download") {
                                self.createBottleProgress = 0
                            } else {
                                self.createBottleProgress = nil
                            }
                        }
                    },
                    progress: { frac in
                        Task { @MainActor in
                            self.createBottleProgress = frac
                        }
                    }
                )

                bottle.settings.windowsVersion = winVersion
                bottle.settings.name = bottleName

                bottle.settings.metalHud = initialMetalHud

                bottle.settings.hk4eSteamPatch = initialSteamPatch
                bottle.settings.hk4eCustomResolutionEnabled = initialCustomResolutionEnabled
                bottle.settings.hk4eCustomResolutionWidth = initialCustomResolutionWidth
                bottle.settings.hk4eCustomResolutionHeight = initialCustomResolutionHeight

                await MainActor.run {
                    self.createBottleStatus = "Initializing Wine prefix"
                    self.createBottleProgress = nil
                }
                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
                let wineVer = try await Wine.wineVersion(bottle: bottle)
                bottle.settings.wineVersion = SemanticVersion(wineVer) ?? SemanticVersion(0, 0, 0)

                if initialRetinaMode {
                    await MainActor.run { self.createBottleStatus = "Applying Retina mode" }
                    try await Wine.changeRetinaMode(bottle: bottle, retinaMode: true)
                }

                if initialSteamPatch {
                    await MainActor.run {
                        self.createBottleStatus = "Applying SteamPatch"
                        self.createBottleProgress = nil
                    }
                    try await SteamPatch.apply(
                        prefixURL: bottle.url,
                        status: { message in
                            Task { @MainActor in
                                self.createBottleStatus = message
                            }
                        },
                        progress: { frac in
                            Task { @MainActor in
                                self.createBottleProgress = frac
                            }
                        }
                    )
                }

                if initialCustomResolutionEnabled {
                    await MainActor.run {
                        self.createBottleStatus = "Waiting for wineserver"
                        self.createBottleProgress = nil
                    }
                    do {
                        for await _ in try Wine.runWineserverProcess(args: ["-w"], bottle: bottle) { }
                    } catch {
                        // best-effort
                    }

                    await MainActor.run { self.createBottleStatus = "Applying custom resolution" }
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
                    self.createBottleStatus = "Finalizing"
                    self.bottlesList.paths.append(newBottleDir)
                    self.loadBottles()
                    self.createdBottleURL = newBottleDir
                    self.isCreatingBottle = false
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

                await MainActor.run {
                    self.createBottleErrorMessage = error.localizedDescription
                    self.isCreatingBottle = false
                    self.createBottleProgress = nil
                    self.createBottleStatus = "Failed"
                }
            }
        }
        return newBottleDir
    }
}
