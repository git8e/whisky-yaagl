//
//  BottleCreationView.swift
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

import SwiftUI
import WhiskyKit

struct BottleCreationView: View {
    @Binding var newlyCreatedBottleURL: URL?

    @ObservedObject private var bottleVM = BottleVM.shared

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var wineRuntimeId: String = "11.4-dxmt-signed"
    @State private var initialRetinaMode: Bool = false

    private enum GameRegionPreset: String, CaseIterable, Sendable {
        case hk4eOs
        case hk4eCn
        case napOs
        case napCn

        var isHK4e: Bool { self == .hk4eOs || self == .hk4eCn }
        var isNAP: Bool { self == .napOs || self == .napCn }

        var gamePreset: BottleVM.GamePreset { isHK4e ? .hk4e : .nap }
        var hk4eRegion: HK4eGame.Region { self == .hk4eCn ? .cn : .os }
        var napRegion: NapGame.Region { self == .napCn ? .cn : .os }
    }

    @State private var gameRegionPreset: GameRegionPreset = .hk4eOs

    @State private var initialSteamPatch: Bool = true
    @State private var initialEnableHDR: Bool = false

    @State private var initialNapFixWebview: Bool = true

    @State private var initialProxyEnabled: Bool = false
    @State private var initialProxyHost: String = ""
    @State private var initialProxyPort: String = ""
    @State private var initialCustomResolutionEnabled: Bool = false
    @State private var initialCustomResolutionWidth: Int = 1920
    @State private var initialCustomResolutionHeight: Int = 1080

    @State private var initialNapCustomResolutionEnabled: Bool = false
    @State private var initialNapCustomResolutionWidth: Int = 1920
    @State private var initialNapCustomResolutionHeight: Int = 1080
    @State private var pinProgramURL: URL?
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir
    @State private var nameValid: Bool = false

    @Environment(\.dismiss) private var dismiss

    private func normalizeProxyFields() {
        // If user pastes "host:port" into host field, split it.
        let host = initialProxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = initialProxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard port.isEmpty else { return }

        let parts = host.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return } // avoid IPv6 / URLs

        let newHost = String(parts[0])
        let newPort = String(parts[1])
        if newHost != initialProxyHost { initialProxyHost = newHost }
        if newPort != initialProxyPort { initialProxyPort = newPort }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("create.name", text: $newBottleName)
                    .onChange(of: newBottleName) { _, name in
                        nameValid = !name.isEmpty
                    }

                Picker("create.win", selection: $newBottleVersion) {
                    ForEach(WinVersion.allCases.reversed(), id: \.self) {
                        Text($0.pretty())
                    }
                }

                Picker("create.wineRuntime", selection: $wineRuntimeId) {
                    ForEach(WineRuntimes.all, id: \.id) { runtime in
                        let installed = WineRuntimeManager.isInstalled(runtimeId: runtime.id)
                        Text(installed ? "\(runtime.displayName)" : "\(runtime.displayName) (Not Installed)")
                            .tag(runtime.id)
                    }
                }

                ActionView(
                    text: "create.path",
                    subtitle: newBottleURL.prettyPath(),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    panel.directoryURL = BottleData.defaultBottleDir
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            newBottleURL = url
                        }
                    }
                }

                Toggle("config.retinaMode", isOn: $initialRetinaMode)

                Picker("create.gameRegion", selection: $gameRegionPreset) {
                    Text("hk4e.region.os").tag(GameRegionPreset.hk4eOs)
                    Text("hk4e.region.cn").tag(GameRegionPreset.hk4eCn)
                    Text("nap.region.os").tag(GameRegionPreset.napOs)
                    Text("nap.region.cn").tag(GameRegionPreset.napCn)
                }

                if gameRegionPreset.isHK4e {
                    Toggle("hk4e.steamPatch", isOn: $initialSteamPatch)
                    Toggle("hk4e.enableHDR", isOn: $initialEnableHDR)
                } else {
                    Toggle("nap.fixWebview", isOn: $initialNapFixWebview)
                }

                Toggle("config.proxy.enable", isOn: $initialProxyEnabled)
                if initialProxyEnabled {
                    HStack(alignment: .center) {
                        TextField("", text: $initialProxyHost, prompt: Text("config.proxy.host"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 188)
                            .onChange(of: initialProxyHost) { _, _ in normalizeProxyFields() }
                        TextField("", text: $initialProxyPort, prompt: Text("config.proxy.port"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                    }
                }

                if gameRegionPreset.isHK4e {
                    Toggle("hk4e.customResolution", isOn: $initialCustomResolutionEnabled)
                    if initialCustomResolutionEnabled {
                        HStack(alignment: .center) {
                            TextField("hk4e.width", value: $initialCustomResolutionWidth, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text("x")
                                .frame(width: 12, height: 28, alignment: .center)
                                .foregroundStyle(.secondary)
                            TextField("hk4e.height", value: $initialCustomResolutionHeight, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                    }
                } else {
                    Toggle("nap.customResolution", isOn: $initialNapCustomResolutionEnabled)
                    if initialNapCustomResolutionEnabled {
                        HStack(alignment: .center) {
                            TextField("nap.width", value: $initialNapCustomResolutionWidth, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text("x")
                                .frame(width: 12, height: 28, alignment: .center)
                                .foregroundStyle(.secondary)
                            TextField("nap.height", value: $initialNapCustomResolutionHeight, formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                    }
                }

                ActionView(
                    text: gameRegionPreset.isHK4e ? "hk4e.gameExecutableOptional" : "nap.gameExecutableOptional",
                    subtitle: pinProgramURL?.path(percentEncoded: false)
                        ?? String(localized: gameRegionPreset.isHK4e ? "hk4e.notSelected" : "nap.notSelected"),
                    actionName: "create.browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            pinProgramURL = url

                            let lower = url.lastPathComponent.lowercased()
                            if lower.contains("zenlesszonezero") {
                                gameRegionPreset = .napOs
                            } else if lower.contains("yuanshen") {
                                gameRegionPreset = .hk4eCn
                            } else if lower.contains("genshinimpact") {
                                gameRegionPreset = .hk4eOs
                            }
                        }
                    }
                }

                if bottleVM.isCreatingBottle {
                    Section("create.progress.title") {
                        Text(bottleVM.createBottleStatus)
                            .foregroundStyle(.secondary)
                        if let progress = bottleVM.createBottleProgress {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(bottleVM.isCreatingBottle)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("create.create") {
                        submit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!nameValid || bottleVM.isCreatingBottle)
                }
            }
            .onSubmit {
                submit()
            }
            .alert(
                "create.error.title",
                isPresented: Binding(
                    get: { bottleVM.createBottleErrorMessage != nil },
                    set: { presenting in
                        if !presenting { bottleVM.createBottleErrorMessage = nil }
                    }
                )
            ) {
                Button("button.ok", role: .cancel) {}
            } message: {
                Text(bottleVM.createBottleErrorMessage ?? String(localized: "create.error.unknown"))
            }
            .onChange(of: bottleVM.createdBottleURL) { _, url in
                guard let url else { return }
                newlyCreatedBottleURL = url
                dismiss()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: ViewWidth.small)
    }

    func submit() {
        let preset = gameRegionPreset.gamePreset
        let hk4eSteamPatch = (preset == .hk4e) ? initialSteamPatch : false
        let hk4eEnableHDR = (preset == .hk4e) ? initialEnableHDR : false
        let hk4eCustomResolutionEnabled = (preset == .hk4e) ? initialCustomResolutionEnabled : false

        let napFixWebview = (preset == .nap) ? initialNapFixWebview : true
        let napCustomResolutionEnabled = (preset == .nap) ? initialNapCustomResolutionEnabled : false

        _ = bottleVM.createNewBottle(
            bottleName: newBottleName,
            winVersion: newBottleVersion,
            bottleURL: newBottleURL,
            wineRuntimeId: wineRuntimeId,
            initialRetinaMode: initialRetinaMode,
            gamePreset: preset,
            initialHK4eRegion: gameRegionPreset.hk4eRegion,
            initialSteamPatch: hk4eSteamPatch,
            initialEnableHDR: hk4eEnableHDR,
            initialNapRegion: gameRegionPreset.napRegion,
            initialNapFixWebview: napFixWebview,
            initialProxyEnabled: initialProxyEnabled,
            initialProxyHost: initialProxyHost,
            initialProxyPort: initialProxyPort,
            initialCustomResolutionEnabled: hk4eCustomResolutionEnabled,
            initialCustomResolutionWidth: initialCustomResolutionWidth,
            initialCustomResolutionHeight: initialCustomResolutionHeight,
            initialNapCustomResolutionEnabled: napCustomResolutionEnabled,
            initialNapCustomResolutionWidth: initialNapCustomResolutionWidth,
            initialNapCustomResolutionHeight: initialNapCustomResolutionHeight,
            pinProgramURL: pinProgramURL
        )
    }
}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
