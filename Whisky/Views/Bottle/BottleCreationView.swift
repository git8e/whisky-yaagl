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
    @State private var wineArchiveURL: URL?
    @State private var initialMetalHud: Bool = false
    @State private var initialRetinaMode: Bool = false
    @State private var initialSteamPatch: Bool = false
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

                Picker("Wine", selection: $wineRuntimeId) {
                    ForEach(WineRuntimes.all, id: \.id) { runtime in
                        let installed = WineRuntimeManager.isInstalled(runtimeId: runtime.id)
                        Text(installed ? "\(runtime.displayName)" : "\(runtime.displayName) (Not Installed)")
                            .tag(runtime.id)
                    }
                }
                .onChange(of: wineRuntimeId) { _, newValue in
                    if newValue == WineRuntimes.whiskyDefaultId {
                        wineArchiveURL = nil
                    }
                }

                if wineRuntimeId != WineRuntimes.whiskyDefaultId {
                    ActionView(
                        text: "Wine Archive (Optional)",
                        subtitle: wineArchiveURL?.path(percentEncoded: false) ?? "Auto download on create",
                        actionName: "Browse"
                    ) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                wineArchiveURL = url
                            }
                        }
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

                Toggle("Metal HUD", isOn: $initialMetalHud)
                Toggle("Retina mode", isOn: $initialRetinaMode)

                Toggle("SteamPatch", isOn: $initialSteamPatch)

                Toggle("Custom resolution", isOn: $initialCustomResolutionEnabled)
                if initialCustomResolutionEnabled {
                    HStack {
                        TextField("Width", value: $initialCustomResolutionWidth, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Text("x")
                            .foregroundStyle(.secondary)
                        TextField("Height", value: $initialCustomResolutionHeight, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                }

                ActionView(
                    text: "Game Executable (Optional)",
                    subtitle: pinProgramURL?.path(percentEncoded: false) ?? "Not selected",
                    actionName: "Browse"
                ) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.begin { result in
                        if result == .OK, let url = panel.urls.first {
                            pinProgramURL = url
                        }
                    }
                }

                if bottleVM.isCreatingBottle {
                    Section("Creating") {
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
                "Create Bottle Failed",
                isPresented: Binding(
                    get: { bottleVM.createBottleErrorMessage != nil },
                    set: { presenting in
                        if !presenting { bottleVM.createBottleErrorMessage = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bottleVM.createBottleErrorMessage ?? "Unknown error")
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
            wineArchiveURL: wineArchiveURL,
            initialMetalHud: initialMetalHud,
            initialRetinaMode: initialRetinaMode,
            initialSteamPatch: initialSteamPatch,
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
