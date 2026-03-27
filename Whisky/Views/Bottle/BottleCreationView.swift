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
    @State private var wineRuntimeId: String = "11.0-dxmt-signed"
    @State private var initialRetinaMode: Bool = false
    @State private var initialHK4eRegion: HK4eGame.Region = .os
    @State private var initialSteamPatch: Bool = true
    @State private var initialEnableHDR: Bool = false
    @State private var initialProxyEnabled: Bool = false
    @State private var initialProxyHost: String = ""
    @State private var initialProxyPort: String = ""
    @State private var initialCustomResolutionEnabled: Bool = false
    @State private var initialCustomResolutionWidth: Int = 1920
    @State private var initialCustomResolutionHeight: Int = 1080
    @State private var pinProgramURL: URL?
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir
    @State private var nameValid: Bool = false

    @Environment(\.dismiss) private var dismiss

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

                Picker("hk4e.region", selection: $initialHK4eRegion) {
                    Text("hk4e.region.os").tag(HK4eGame.Region.os)
                    Text("hk4e.region.cn").tag(HK4eGame.Region.cn)
                }

                Toggle("hk4e.steamPatch", isOn: $initialSteamPatch)

                Toggle("hk4e.enableHDR", isOn: $initialEnableHDR)

                Toggle("config.proxy.enable", isOn: $initialProxyEnabled)
                if initialProxyEnabled {
                    HStack(alignment: .center) {
                        TextField("config.proxy.host", text: $initialProxyHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                        Text(":")
                            .foregroundStyle(.secondary)
                        TextField("config.proxy.port", text: $initialProxyPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }

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

                ActionView(
                    text: "hk4e.gameExecutableOptional",
                    subtitle: pinProgramURL?.path(percentEncoded: false) ?? String(localized: "hk4e.notSelected"),
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
                            if lower.contains("yuanshen") {
                                initialHK4eRegion = .cn
                            } else if lower.contains("genshinimpact") {
                                initialHK4eRegion = .os
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
        _ = bottleVM.createNewBottle(
            bottleName: newBottleName,
            winVersion: newBottleVersion,
            bottleURL: newBottleURL,
            wineRuntimeId: wineRuntimeId,
            initialRetinaMode: initialRetinaMode,
            initialHK4eRegion: initialHK4eRegion,
            initialSteamPatch: initialSteamPatch,
            initialEnableHDR: initialEnableHDR,
            initialProxyEnabled: initialProxyEnabled,
            initialProxyHost: initialProxyHost,
            initialProxyPort: initialProxyPort,
            initialCustomResolutionEnabled: initialCustomResolutionEnabled,
            initialCustomResolutionWidth: initialCustomResolutionWidth,
            initialCustomResolutionHeight: initialCustomResolutionHeight,
            pinProgramURL: pinProgramURL
        )
    }
}

#Preview {
    BottleCreationView(newlyCreatedBottleURL: .constant(nil))
}
