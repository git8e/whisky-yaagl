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
import UniformTypeIdentifiers

struct BottleCreationView: View {
    @Binding var newlyCreatedBottleURL: URL?

    @ObservedObject private var bottleVM = BottleVM.shared

    @State private var newBottleName: String = ""
    @State private var newBottleVersion: WinVersion = .win10
    @State private var wineRuntimeId: String = WineRuntimes.defaultRuntimeId
    @State private var availableRuntimes: [WineRuntime] = WineRuntimes.all
    @State private var initialRetinaMode: Bool = false

    private enum GameRegionPreset: String, CaseIterable, Sendable {
        case hk4eOs
        case hk4eCn
        case napOs
        case napCn
        case hkrpgOs
        case hkrpgCn

        var isHK4e: Bool { self == .hk4eOs || self == .hk4eCn }
        var isNAP: Bool { self == .napOs || self == .napCn }
        var isHKRPG: Bool { self == .hkrpgOs || self == .hkrpgCn }

        var gamePreset: BottleVM.GamePreset {
            if isHK4e { return .hk4e }
            if isNAP { return .nap }
            return .hkrpg
        }
        var hk4eRegion: HK4eGame.Region { self == .hk4eCn ? .cn : .os }
        var napRegion: NapGame.Region { self == .napCn ? .cn : .os }
        var hkrpgRegion: HKRPGGame.Region { self == .hkrpgCn ? .cn : .os }
    }

    @State private var gameRegionPreset: GameRegionPreset = .hk4eOs

    @State private var initialHK4eLaunchFixBlockNetwork: Bool = false
    @State private var initialNapLaunchFixBlockNetwork: Bool = true
    @State private var initialHKRPGLaunchFixBlockNetwork: Bool = false
    @State private var initialHK4eLeftCommandIsCtrl: Bool = false
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
    @State private var otherSettingsExpanded: Bool = false
    @State private var pinProgramURL: URL?
    @State private var newBottleURL: URL = UserDefaults.standard.url(forKey: "defaultBottleLocation")
                                           ?? BottleData.defaultBottleDir
    @State private var nameValid: Bool = false

    @Environment(\.dismiss) private var dismiss

    private var gameExecutableOptionalKey: LocalizedStringKey {
        if gameRegionPreset.isHK4e { return "hk4e.gameExecutableOptional" }
        if gameRegionPreset.isNAP { return "nap.gameExecutableOptional" }
        return "hkrpg.gameExecutableOptional"
    }

    private var gameNotSelectedKey: String.LocalizationValue {
        if gameRegionPreset.isHK4e { return "hk4e.notSelected" }
        if gameRegionPreset.isNAP { return "nap.notSelected" }
        return "hkrpg.notSelected"
    }

    private var exeHintKey: LocalizedStringKey {
        switch gameRegionPreset {
        case .hk4eOs:
            return "hk4e.exeHint.os"
        case .hk4eCn:
            return "hk4e.exeHint.cn"
        case .napOs:
            return "nap.exeHint.os"
        case .napCn:
            return "nap.exeHint.cn"
        case .hkrpgOs:
            return "hkrpg.exeHint.os"
        case .hkrpgCn:
            return "hkrpg.exeHint.cn"
        }
    }

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
                nameField
                windowsPicker
                runtimePicker
                bottlePathPicker
                Toggle("config.retinaMode", isOn: $initialRetinaMode)
                regionPicker
                executablePicker
                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            otherSettingsExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("create.otherSettings")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(otherSettingsExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if otherSettingsExpanded {
                        proxySettings
                        resolutionSettings
                        gameSpecificToggles

                        Text("patchOptions.keepDefaultHint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        .task {
            availableRuntimes = await WineRuntimes.refreshCatalog(forceRemote: false)
            if !availableRuntimes.contains(where: { $0.id == wineRuntimeId }) {
                wineRuntimeId = WineRuntimes.defaultRuntimeId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WineRuntimes.didUpdateNotification)) { _ in
            availableRuntimes = WineRuntimes.all
            if !availableRuntimes.contains(where: { $0.id == wineRuntimeId }) {
                wineRuntimeId = WineRuntimes.defaultRuntimeId
            }
        }
    }

    private var nameField: some View {
        TextField("create.name", text: $newBottleName)
            .onChange(of: newBottleName) { _, name in
                nameValid = !name.isEmpty
            }
    }

    private var windowsPicker: some View {
        Picker("create.win", selection: $newBottleVersion) {
            ForEach(WinVersion.allCases.reversed(), id: \.self) {
                Text($0.pretty())
            }
        }
    }

    private var runtimePicker: some View {
        Picker("create.wineRuntime", selection: $wineRuntimeId) {
            ForEach(availableRuntimes, id: \.id) { runtime in
                let installed = WineRuntimeManager.isInstalled(runtimeId: runtime.id)
                let notInstalledLabel = String(localized: "runtime.status.notInstalled")
                Text(installed ? "\(runtime.displayName)" : "\(runtime.displayName) (\(notInstalledLabel))")
                    .tag(runtime.id)
            }
        }
    }

    private var bottlePathPicker: some View {
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
    }

    private var regionPicker: some View {
        Picker("create.gameRegion", selection: $gameRegionPreset) {
            Text("hk4e.region.os").tag(GameRegionPreset.hk4eOs)
            Text("hk4e.region.cn").tag(GameRegionPreset.hk4eCn)
            Text("nap.region.os").tag(GameRegionPreset.napOs)
            Text("nap.region.cn").tag(GameRegionPreset.napCn)
            Text("hkrpg.region.os").tag(GameRegionPreset.hkrpgOs)
            Text("hkrpg.region.cn").tag(GameRegionPreset.hkrpgCn)
        }
    }

    @ViewBuilder
    private var gameSpecificToggles: some View {
        if gameRegionPreset.isHK4e {
            Toggle("hk4e.enableHDR", isOn: $initialEnableHDR)
            Toggle("hk4e.launchFixBlockNetwork", isOn: $initialHK4eLaunchFixBlockNetwork)
            Toggle("hk4e.leftCommandIsCtrl", isOn: $initialHK4eLeftCommandIsCtrl)
            Toggle("hk4e.steamPatch", isOn: $initialSteamPatch)
        } else if gameRegionPreset.isNAP {
            Toggle("nap.launchFixBlockNetwork", isOn: $initialNapLaunchFixBlockNetwork)
            Toggle("nap.fixWebview", isOn: $initialNapFixWebview)
        } else {
            Toggle("hkrpg.launchFixBlockNetwork", isOn: $initialHKRPGLaunchFixBlockNetwork)
        }
    }

    @ViewBuilder
    private var proxySettings: some View {
        Toggle("config.proxy.enable", isOn: $initialProxyEnabled)
        if initialProxyEnabled {
            HStack(alignment: .center, spacing: 2) {
                TextField("", text: $initialProxyHost, prompt: Text("config.proxy.host"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 182)
                    .onChange(of: initialProxyHost) { _, _ in normalizeProxyFields() }
                Text(":")
                    .foregroundStyle(.secondary)
                    .frame(width: 6)
                TextField("", text: $initialProxyPort, prompt: Text("config.proxy.port"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
            }
        }
    }

    @ViewBuilder
    private var resolutionSettings: some View {
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
        } else if gameRegionPreset.isNAP {
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
    }

    private var executablePicker: some View {
        Group {
            ActionView(
                text: gameExecutableOptionalKey,
                subtitle: pinProgramURL?.path(percentEncoded: false) ?? String(localized: gameNotSelectedKey),
                actionName: "create.browse"
            ) {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.allowedContentTypes = [UTType.exe]
                panel.message = String(localized: "exePicker.panelMessage")
                panel.begin { result in
                    if result == .OK, let url = panel.urls.first {
                        pinProgramURL = url

                        let lower = url.lastPathComponent.lowercased()
                        if lower.contains("zenlesszonezero") {
                            gameRegionPreset = .napOs
                        } else if lower.contains("starrail") {
                            gameRegionPreset = .hkrpgOs
                        } else if lower.contains("yuanshen") {
                            gameRegionPreset = .hk4eCn
                        } else if lower.contains("genshinimpact") {
                            gameRegionPreset = .hk4eOs
                        }
                    }
                }
            }

            Text(exeHintKey)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("exePicker.leaveBlankHint")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    func submit() {
        guard bottleVM.isCreatingBottle == false else { return }

        if otherSettingsExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                otherSettingsExpanded = false
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                performCreate()
            }
            return
        }

        performCreate()
    }

    private func performCreate() {
        let preset = gameRegionPreset.gamePreset
        let hk4eLaunchFixBlockNetwork = (preset == .hk4e) ? initialHK4eLaunchFixBlockNetwork : false
        let napLaunchFixBlockNetwork = (preset == .nap) ? initialNapLaunchFixBlockNetwork : false
        let hkrpgLaunchFixBlockNetwork = (preset == .hkrpg) ? initialHKRPGLaunchFixBlockNetwork : false
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
            initialLaunchFixBlockNetwork: hk4eLaunchFixBlockNetwork,
            initialHK4eLeftCommandIsCtrl: initialHK4eLeftCommandIsCtrl,
            initialSteamPatch: hk4eSteamPatch,
            initialEnableHDR: hk4eEnableHDR,
            initialNapRegion: gameRegionPreset.napRegion,
            initialNapLaunchFixBlockNetwork: napLaunchFixBlockNetwork,
            initialNapFixWebview: napFixWebview,
            initialHKRPGRegion: gameRegionPreset.hkrpgRegion,
            initialHKRPGLaunchFixBlockNetwork: hkrpgLaunchFixBlockNetwork,
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
