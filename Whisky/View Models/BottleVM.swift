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
import WhiskyKit

// swiftlint:disable:next todo
// TODO: Don't use unchecked!
final class BottleVM: ObservableObject, @unchecked Sendable {
    @MainActor static let shared = BottleVM()

    enum GamePreset: String, CaseIterable, Sendable {
        case hk4e
        case nap
    }

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
        gamePreset: GamePreset = .hk4e,
        initialHK4eRegion: HK4eGame.Region = .os,
        initialSteamPatch: Bool = false,
        initialCertImport: Bool = true,
        initialEnableHDR: Bool = false,
        initialNapRegion: NapGame.Region = .os,
        initialNapFixWebview: Bool = true,
        initialProxyEnabled: Bool = false,
        initialProxyHost: String = "",
        initialProxyPort: String = "",
        initialCustomResolutionEnabled: Bool = false,
        initialCustomResolutionWidth: Int = 1920,
        initialCustomResolutionHeight: Int = 1080,
        initialNapCustomResolutionEnabled: Bool = false,
        initialNapCustomResolutionWidth: Int = 1920,
        initialNapCustomResolutionHeight: Int = 1080,
        pinProgramURL: URL? = nil
    ) -> URL {
        let newBottleDir = bottleURL.appending(path: UUID().uuidString)

        Task { @MainActor in
            self.isCreatingBottle = true
            self.createBottleStatus = String(localized: "create.status.preparing")
            self.createBottleProgress = nil
            self.createBottleErrorMessage = nil
            self.createdBottleURL = nil
        }

        Task.detached {
            var bottleId: Bottle?
            do {
                await MainActor.run {
                    self.createBottleStatus = String(localized: "create.status.directory")
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

                bottle.settings.gamePreset = (gamePreset == .nap) ? .nap : .hk4e

                bottle.settings.hk4eRegion = initialHK4eRegion
                bottle.settings.hk4eSteamPatch = initialSteamPatch
                bottle.settings.hk4eCertificateImportEnabled = initialCertImport
                bottle.settings.hk4eEnableHDR = initialEnableHDR
                bottle.settings.hk4eLaunchPatchingEnabled = (gamePreset == .hk4e)

                bottle.settings.napRegion = initialNapRegion
                bottle.settings.napFixWebview = initialNapFixWebview
                bottle.settings.napCustomResolutionEnabled = initialNapCustomResolutionEnabled
                bottle.settings.napCustomResolutionWidth = initialNapCustomResolutionWidth
                bottle.settings.napCustomResolutionHeight = initialNapCustomResolutionHeight
                bottle.settings.proxyEnabled = initialProxyEnabled
                bottle.settings.proxyHost = initialProxyHost
                bottle.settings.proxyPort = initialProxyPort
                bottle.settings.hk4eCustomResolutionEnabled = initialCustomResolutionEnabled
                bottle.settings.hk4eCustomResolutionWidth = initialCustomResolutionWidth
                bottle.settings.hk4eCustomResolutionHeight = initialCustomResolutionHeight

                try await Wine.withLogSession(for: bottle) {
                    await MainActor.run {
                        self.createBottleStatus = String(localized: "create.status.initializingPrefix")
                        self.createBottleProgress = nil
                    }

                    // YAAGL-style initialization: explicitly wineboot + wait, then set Win version.
                    let initEnv: [String: String] = [
                        // Prevent winemenubuilder failures from aborting initialization.
                        // (Some Wine builds may not ship winemenubuilder.exe in system32.)
                        "WINEDLLOVERRIDES": "winemenubuilder.exe=d",
                        // Keep bootstrap noise from surfacing as fatal errors.
                        "WINEDEBUG": "-all",
                        // Avoid MSYNC/ESYNC overhead during prefix init.
                        "WINEESYNC": "0",
                        "WINEMSYNC": "0"
                    ]

                    if gamePreset == .hk4e, bottle.settings.hk4eCertificateImportEnabled {
                        await MainActor.run { self.createBottleStatus = String(localized: "create.status.certificates") }
                        do {
                            try await HK4eWineCertificates.ensurePatched(runtimeId: wineRuntimeId)
                        } catch {
                            await MainActor.run {
                                self.createBottleStatus = String(
                                    format: String(localized: "create.status.certificatesIgnored"),
                                    error.localizedDescription
                                )
                            }
                        }
                    }

                    await MainActor.run { self.createBottleStatus = String(localized: "create.status.wineboot") }
                    _ = try await Wine.runWine(["wineboot", "-u"], bottle: bottle, environment: initEnv)

                    if winVersion != .win10 {
                        await MainActor.run { self.createBottleStatus = String(localized: "create.status.windowsVersion") }
                        _ = try await Wine.runWine(["winecfg", "-v", winVersion.rawValue], bottle: bottle, environment: initEnv)
                    }

                    if gamePreset == .hk4e {
                        // Pre-configure HK4e-related patch dependencies so the bottle is ready before first launch.
                        if bottle.settings.hk4eDXMTInjectionEnabled,
                           let runtime = WineRuntimes.runtime(id: wineRuntimeId),
                           runtime.renderBackend == .dxmt {
                            await MainActor.run { self.createBottleStatus = String(localized: "create.status.hk4e") }
                            try await HK4eDXMT.ensureInstalled(progress: nil)
                            HK4eDXMT.applyToRuntime(runtimeId: wineRuntimeId)
                            try? HK4eDXMT.applyToPrefix(prefixURL: newBottleDir)
                        }

                        if bottle.settings.hk4eSteamPatch {
                            await MainActor.run { self.createBottleStatus = String(localized: "create.status.hk4e") }
                            try? await SteamPatch.apply(prefixURL: newBottleDir)
                        }

                        if bottle.settings.hk4eLeftCommandIsCtrl || bottle.settings.hk4eCustomResolutionEnabled {
                            await MainActor.run { self.createBottleStatus = String(localized: "create.status.hk4e") }
                            try await HK4ePersistentConfig.applyIfNeeded(bottle: bottle)
                        }
                    }

                    if initialRetinaMode {
                        await MainActor.run { self.createBottleStatus = String(localized: "config.retinaMode") }
                        try await Wine.changeRetinaMode(bottle: bottle, retinaMode: true)
                    }

                    if bottle.settings.proxyEnabled ||
                        !bottle.settings.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !bottle.settings.proxyPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await MainActor.run { self.createBottleStatus = String(localized: "config.proxy.status") }
                        try await WineProxySettings.applyIfNeeded(bottle: bottle)
                    }
                }

                // Custom resolution is applied per-launch (YAAGL-style), not during bottle creation.

                if let pinProgramURL {
                    bottle.settings.pins.append(
                        PinnedProgram(name: pinProgramURL.deletingPathExtension().lastPathComponent, url: pinProgramURL)
                    )
                    switch gamePreset {
                    case .hk4e:
                        bottle.settings.hk4eGameExecutableURL = pinProgramURL
                    case .nap:
                        bottle.settings.napGameExecutableURL = pinProgramURL
                    }
                }

                // Add record
                await MainActor.run {
                    self.createBottleStatus = String(localized: "create.status.finalizing")
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
                    self.createBottleStatus = String(localized: "create.status.failed")
                }
            }
        }
        return newBottleDir
    }
}
