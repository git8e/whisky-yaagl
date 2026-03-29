//
//  ConfigView.swift
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
import AppKit
import WhiskyKit

enum LoadingState {
    case loading
    case modifying
    case success
    case failed
}

struct ConfigView: View {
    @ObservedObject var bottle: Bottle
    @State private var buildVersion: Int = 0
    @State private var retinaMode: Bool = false
    @State private var dpiConfig: Int = 96
    @State private var proxyEnabled: Bool = false
    @State private var proxyHost: String = ""
    @State private var proxyPort: String = ""

    @State private var runtimeInstallLoadingState: LoadingState = .success
    @State private var runtimeWineVersion: String? = nil
    @State private var isRevertingRuntimeSelection: Bool = false
    @State private var winVersionLoadingState: LoadingState = .loading
    @State private var buildVersionLoadingState: LoadingState = .loading
    @State private var retinaModeLoadingState: LoadingState = .loading
    @State private var dpiConfigLoadingState: LoadingState = .loading
    @State private var proxyLoadingState: LoadingState = .success
    @State private var dpiSheetPresented: Bool = false
    @AppStorage("wineSectionExpanded") private var wineSectionExpanded: Bool = true
    @AppStorage("dxvkSectionExpanded") private var dxvkSectionExpanded: Bool = true
    @AppStorage("metalSectionExpanded") private var metalSectionExpanded: Bool = true
    @AppStorage("hk4eSectionExpanded") private var hk4eSectionExpanded: Bool = true

    private enum GameRegionPreset: String, CaseIterable, Identifiable, Sendable {
        case hk4eOs
        case hk4eCn
        case napOs
        case napCn
        case hkrpgOs
        case hkrpgCn

        var id: String { rawValue }

        var isHK4e: Bool { self == .hk4eOs || self == .hk4eCn }
        var isNAP: Bool { self == .napOs || self == .napCn }
        var isHKRPG: Bool { self == .hkrpgOs || self == .hkrpgCn }

        var gamePreset: BottleGamePreset {
            if isHK4e { return .hk4e }
            if isNAP { return .nap }
            return .hkrpg
        }
        var hk4eRegion: HK4eGame.Region { self == .hk4eCn ? .cn : .os }
        var napRegion: NapGame.Region { self == .napCn ? .cn : .os }
        var hkrpgRegion: HKRPGGame.Region { self == .hkrpgCn ? .cn : .os }
    }

    private var gameRegionSelection: Binding<GameRegionPreset> {
        Binding(
            get: {
                switch bottle.settings.gamePreset {
                case .nap:
                    return bottle.settings.napRegion == .cn ? .napCn : .napOs
                case .hk4e:
                    return bottle.settings.hk4eRegion == .cn ? .hk4eCn : .hk4eOs
                case .hkrpg:
                    return bottle.settings.hkrpgRegion == .cn ? .hkrpgCn : .hkrpgOs
                }
            },
            set: { preset in
                bottle.settings.gamePreset = preset.gamePreset
                if preset.isHK4e {
                    bottle.settings.hk4eRegion = preset.hk4eRegion
                    bottle.settings.hk4eLaunchPatchingEnabled = true
                    bottle.settings.hkrpgLaunchPatchingEnabled = false
                } else if preset.isNAP {
                    bottle.settings.napRegion = preset.napRegion
                    bottle.settings.hk4eLaunchPatchingEnabled = false
                    bottle.settings.hkrpgLaunchPatchingEnabled = false
                } else {
                    bottle.settings.hkrpgRegion = preset.hkrpgRegion
                    bottle.settings.hkrpgLaunchPatchingEnabled = true
                    bottle.settings.hk4eLaunchPatchingEnabled = false
                }
            }
        )
    }

    private var isDXMTRuntime: Bool {
        WineRuntimes.runtime(id: bottle.settings.wineRuntimeId)?.renderBackend == .dxmt
    }

    var body: some View {
        Form {
            Section("config.title.wine", isExpanded: $wineSectionExpanded) {
                SettingItemView(title: "config.wineRuntime", loadingState: runtimeInstallLoadingState) {
                    Picker("config.wineRuntime", selection: $bottle.settings.wineRuntimeId) {
                        ForEach(WineRuntimes.all, id: \.id) { runtime in
                            let installed = WineRuntimeManager.isInstalled(runtimeId: runtime.id)
                            let suffix: String = {
                                if runtime.id == bottle.settings.wineRuntimeId, let v = runtimeWineVersion, !v.isEmpty {
                                    return " (\(v))"
                                }
                                if !installed {
                                    return " (Not Installed)"
                                }
                                return ""
                            }()
                            Text("\(runtime.displayName)\(suffix)").tag(runtime.id)
                        }
                    }
                    .onChange(of: bottle.settings.wineRuntimeId) { oldRuntimeId, newRuntimeId in
                        guard isRevertingRuntimeSelection == false else { return }

                        runtimeInstallLoadingState = .modifying
                        Task(priority: .userInitiated) {
                            do {
                                try await WineRuntimeManager.ensureInstalled(runtimeId: newRuntimeId)

                                // Rebuild isolated runtime to match the newly selected base runtime.
                                try await WineRuntimeManager.ensureIsolatedRuntime(
                                    bottle: bottle,
                                    baseRuntimeId: newRuntimeId
                                )

                                let version = try? await Wine.wineVersion(bottle: bottle)
                                await MainActor.run {
                                    runtimeWineVersion = version
                                    runtimeInstallLoadingState = .success
                                }
                            } catch {
                                await MainActor.run {
                                    isRevertingRuntimeSelection = true
                                    bottle.settings.wineRuntimeId = oldRuntimeId
                                    isRevertingRuntimeSelection = false
                                    runtimeInstallLoadingState = .success
                                }
                            }
                        }
                    }
                }
                SettingItemView(title: "config.winVersion", loadingState: winVersionLoadingState) {
                    Picker("config.winVersion", selection: $bottle.settings.windowsVersion) {
                        ForEach(WinVersion.allCases.reversed(), id: \.self) {
                            Text($0.pretty())
                        }
                    }
                }
                SettingItemView(title: "config.buildVersion", loadingState: buildVersionLoadingState) {
                    TextField("config.buildVersion", value: $buildVersion, formatter: NumberFormatter())
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit {
                            buildVersionLoadingState = .modifying
                            Task(priority: .userInitiated) {
                                do {
                                    try await Wine.changeBuildVersion(bottle: bottle, version: buildVersion)
                                    buildVersionLoadingState = .success
                                } catch {
                                    print("Failed to change build version")
                                    buildVersionLoadingState = .failed
                                }
                            }
                        }
                }
                SettingItemView(title: "config.retinaMode", loadingState: retinaModeLoadingState) {
                    Toggle("config.retinaMode", isOn: $retinaMode)
                        .onChange(of: retinaMode, { _, newValue in
                            Task(priority: .userInitiated) {
                                retinaModeLoadingState = .modifying
                                do {
                                    try await Wine.changeRetinaMode(bottle: bottle, retinaMode: newValue)
                                    retinaModeLoadingState = .success
                                } catch {
                                    print("Failed to change build version")
                                    retinaModeLoadingState = .failed
                                }
                            }
                        })
                }
                Picker("config.enhancedSync", selection: $bottle.settings.enhancedSync) {
                    Text("config.enhancedSync.none").tag(EnhancedSync.none)
                    Text("config.enhacnedSync.esync").tag(EnhancedSync.esync)
                    Text("config.enhacnedSync.msync").tag(EnhancedSync.msync)
                }
                SettingItemView(title: "config.proxy.enable", loadingState: proxyLoadingState) {
                    Toggle("config.proxy.enable", isOn: $proxyEnabled)
                        .labelsHidden()
                        .onChange(of: proxyEnabled) { _, newValue in
                            bottle.settings.proxyEnabled = newValue
                            applyProxySettings()
                        }
                }
                if proxyEnabled {
                    HStack(spacing: 8) {
                        Text(String(localized: "config.proxy.server"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 2) {
                            TextField("", text: $proxyHost, prompt: Text("config.proxy.host"))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 162)
                                .onChange(of: proxyHost) { _, _ in normalizeProxyFields() }
                            Text(":")
                                .foregroundStyle(.secondary)
                                .frame(width: 6)
                            TextField("", text: $proxyPort, prompt: Text("config.proxy.port"))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 86)
                                .onSubmit { applyProxySettings() }
                        }
                        Button("config.proxy.apply") {
                            applyProxySettings()
                        }
                    }
                }
                SettingItemView(title: "config.dpi", loadingState: dpiConfigLoadingState) {
                    Button("config.inspect") {
                        dpiSheetPresented = true
                    }
                    .sheet(isPresented: $dpiSheetPresented) {
                        DPIConfigSheetView(
                            dpiConfig: $dpiConfig,
                            isRetinaMode: $retinaMode,
                            presented: $dpiSheetPresented
                        )
                    }
                }
                if #available(macOS 15, *) {
                    Toggle(isOn: $bottle.settings.avxEnabled) {
                        VStack(alignment: .leading) {
                            Text("config.avx")
                            if bottle.settings.avxEnabled {
                                HStack(alignment: .firstTextBaseline) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .font(.subheadline)
                                    Text("config.avx.warning")
                                        .fontWeight(.light)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            Section("config.title.dxvk", isExpanded: $dxvkSectionExpanded) {
                Toggle(isOn: $bottle.settings.dxvk) {
                    Text("config.dxvk")
                }
                Toggle(isOn: $bottle.settings.dxvkAsync) {
                    Text("config.dxvk.async")
                }
                .disabled(!bottle.settings.dxvk)
                Picker("config.dxvkHud", selection: $bottle.settings.dxvkHud) {
                    Text("config.dxvkHud.full").tag(DXVKHUD.full)
                    Text("config.dxvkHud.partial").tag(DXVKHUD.partial)
                    Text("config.dxvkHud.fps").tag(DXVKHUD.fps)
                    Text("config.dxvkHud.off").tag(DXVKHUD.off)
                }
                .disabled(!bottle.settings.dxvk)
            }
            Section("config.title.metal", isExpanded: $metalSectionExpanded) {
                Toggle(isOn: $bottle.settings.metalHud) {
                    Text("config.metalHud")
                }
                Toggle(isOn: $bottle.settings.metalTrace) {
                    Text("config.metalTrace")
                    Text("config.metalTrace.info")
                }
                if let device = MTLCreateSystemDefaultDevice() {
                    // Represents the Apple family 9 GPU features that correspond to the Apple A17, M3, and M4 GPUs.
                    if device.supportsFamily(.apple9) {
                        Toggle(isOn: $bottle.settings.dxrEnabled) {
                            Text("config.dxr")
                            Text("config.dxr.info")
                        }
                    }
                }
            }

            Section("create.gameRegion", isExpanded: $hk4eSectionExpanded) {
                Picker("create.gameRegion", selection: gameRegionSelection) {
                    Text("hk4e.region.os").tag(GameRegionPreset.hk4eOs)
                    Text("hk4e.region.cn").tag(GameRegionPreset.hk4eCn)
                    Text("nap.region.os").tag(GameRegionPreset.napOs)
                    Text("nap.region.cn").tag(GameRegionPreset.napCn)
                    Text("hkrpg.region.os").tag(GameRegionPreset.hkrpgOs)
                    Text("hkrpg.region.cn").tag(GameRegionPreset.hkrpgCn)
                }

                if gameRegionSelection.wrappedValue.isHK4e {
                    ActionView(
                        text: "hk4e.gameExecutable",
                        subtitle: bottle.settings.hk4eGameExecutableURL?.prettyPath()
                            ?? String(localized: "hk4e.notSelected"),
                        actionName: "create.browse"
                    ) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                let oldURL = bottle.settings.hk4eGameExecutableURL
                                bottle.settings.hk4eGameExecutableURL = url
                                updatePinnedGameExecutable(oldURL: oldURL, newURL: url)
                            }
                        }
                    }

                    Toggle("hk4e.leftCommandIsCtrl", isOn: $bottle.settings.hk4eLeftCommandIsCtrl)
                        .onChange(of: bottle.settings.hk4eLeftCommandIsCtrl) { _, _ in
                            Task(priority: .userInitiated) {
                                try? await HK4ePersistentConfig.applyIfNeeded(bottle: bottle)
                            }
                        }

                    Toggle("hk4e.launchFixBlockNetwork", isOn: $bottle.settings.hk4eLaunchFixBlockNetwork)
                        .onChange(of: bottle.settings.hk4eLaunchFixBlockNetwork) { _, enabled in
                            // If launch fix is turned off, actively restore the bottle's persistent proxy settings.
                            guard enabled == false else { return }
                            Task(priority: .userInitiated) {
                                try? await WineProxySettings.restoreDesiredState(bottle: bottle)
                            }
                        }

                    Toggle("hk4e.steamPatch", isOn: $bottle.settings.hk4eSteamPatch)
                        .onChange(of: bottle.settings.hk4eSteamPatch) { _, enabled in
                            Task(priority: .userInitiated) {
                                if enabled {
                                    try? await SteamPatch.apply(prefixURL: bottle.url)
                                } else {
                                    try? SteamPatch.remove(prefixURL: bottle.url)
                                }
                            }
                        }

                    if isDXMTRuntime {
                        Toggle("hk4e.dxmtInjection", isOn: $bottle.settings.hk4eDXMTInjectionEnabled)
                            .onChange(of: bottle.settings.hk4eDXMTInjectionEnabled) { _, enabled in
                                Task(priority: .userInitiated) {
                                    if enabled {
                                        try? await HK4eDXMT.ensureInstalled(progress: nil)
                                        do {
                                            try await WineRuntimeManager.ensureIsolatedRuntime(
                                                bottle: bottle,
                                                baseRuntimeId: bottle.settings.wineRuntimeId
                                            )
                                            HK4eDXMT.applyToRuntime(runtimeRoot: WineRuntimeManager.effectiveWineRoot(bottle: bottle))
                                        } catch {
                                            return
                                        }
                                        try? HK4eDXMT.applyToPrefix(prefixURL: bottle.url)
                                    } else {
                                        HK4eDXMT.revertPrefix(prefixURL: bottle.url)
                                        let isolated = WineRuntimeManager.isolatedRuntimeRoot(bottleURL: bottle.url)
                                        let isolatedWine64 = isolated.appendingPathComponent("bin/wine64")
                                        let isolatedWine = isolated.appendingPathComponent("bin/wine")
                                        if FileManager.default.fileExists(atPath: isolatedWine64.path(percentEncoded: false)) ||
                                            FileManager.default.fileExists(atPath: isolatedWine.path(percentEncoded: false)) {
                                            HK4eDXMT.revertRuntime(runtimeRoot: isolated)
                                        }
                                    }
                                }
                            }
                    }

                    Toggle("hk4e.enableHDR", isOn: $bottle.settings.hk4eEnableHDR)

                    Toggle("hk4e.customResolution", isOn: $bottle.settings.hk4eCustomResolutionEnabled)
                        .onChange(of: bottle.settings.hk4eCustomResolutionEnabled) { _, _ in
                            Task(priority: .userInitiated) {
                                try? await HK4ePersistentConfig.applyIfNeeded(bottle: bottle)
                            }
                        }
                    HStack(alignment: .center) {
                        TextField(
                            "hk4e.width",
                            value: $bottle.settings.hk4eCustomResolutionWidth,
                            formatter: NumberFormatter()
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        Text("x")
                            .frame(width: 12, height: 28, alignment: .center)
                            .foregroundStyle(.secondary)
                        TextField(
                            "hk4e.height",
                            value: $bottle.settings.hk4eCustomResolutionHeight,
                            formatter: NumberFormatter()
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        Spacer()
                    }

                    Text("hk4e.description")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if gameRegionSelection.wrappedValue.isNAP {
                    ActionView(
                        text: "nap.gameExecutable",
                        subtitle: bottle.settings.napGameExecutableURL?.prettyPath()
                            ?? String(localized: "nap.notSelected"),
                        actionName: "create.browse"
                    ) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                let oldURL = bottle.settings.napGameExecutableURL
                                bottle.settings.napGameExecutableURL = url
                                updatePinnedGameExecutable(oldURL: oldURL, newURL: url)
                            }
                        }
                    }

                    Toggle("nap.launchFixBlockNetwork", isOn: $bottle.settings.napLaunchFixBlockNetwork)
                        .onChange(of: bottle.settings.napLaunchFixBlockNetwork) { _, enabled in
                            guard enabled == false else { return }
                            Task(priority: .userInitiated) {
                                try? await WineProxySettings.restoreDesiredState(bottle: bottle)
                            }
                        }

                    Toggle("nap.fixWebview", isOn: $bottle.settings.napFixWebview)

                    Toggle("nap.customResolution", isOn: $bottle.settings.napCustomResolutionEnabled)
                    HStack(alignment: .center) {
                        TextField(
                            "nap.width",
                            value: $bottle.settings.napCustomResolutionWidth,
                            formatter: NumberFormatter()
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .disabled(!bottle.settings.napCustomResolutionEnabled)
                        Text("x")
                            .frame(width: 12, height: 28, alignment: .center)
                            .foregroundStyle(.secondary)
                        TextField(
                            "nap.height",
                            value: $bottle.settings.napCustomResolutionHeight,
                            formatter: NumberFormatter()
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .disabled(!bottle.settings.napCustomResolutionEnabled)
                        Spacer()
                    }
                } else {
                    ActionView(
                        text: "hkrpg.gameExecutable",
                        subtitle: bottle.settings.hkrpgGameExecutableURL?.prettyPath()
                            ?? String(localized: "hkrpg.notSelected"),
                        actionName: "create.browse"
                    ) {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                let oldURL = bottle.settings.hkrpgGameExecutableURL
                                bottle.settings.hkrpgGameExecutableURL = url
                                updatePinnedGameExecutable(oldURL: oldURL, newURL: url)
                            }
                        }
                    }

                    Toggle("hkrpg.launchFixBlockNetwork", isOn: $bottle.settings.hkrpgLaunchFixBlockNetwork)
                        .onChange(of: bottle.settings.hkrpgLaunchFixBlockNetwork) { _, enabled in
                            guard enabled == false else { return }
                            Task(priority: .userInitiated) {
                                try? await WineProxySettings.restoreDesiredState(bottle: bottle)
                            }
                        }
                }
            }
        }
        .formStyle(.grouped)
        .animation(.whiskyDefault, value: wineSectionExpanded)
        .animation(.whiskyDefault, value: dxvkSectionExpanded)
        .animation(.whiskyDefault, value: metalSectionExpanded)
        .animation(.whiskyDefault, value: hk4eSectionExpanded)
        .bottomBar {
            HStack {
                Spacer()
                Button("config.controlPanel") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.control(bottle: bottle)
                        } catch {
                            print("Failed to launch control")
                        }
                    }
                }
                Button("config.regedit") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.regedit(bottle: bottle)
                        } catch {
                            print("Failed to launch regedit")
                        }
                    }
                }
                Button("config.winecfg") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.cfg(bottle: bottle)
                        } catch {
                            print("Failed to launch winecfg")
                        }
                    }
                }
                Button("button.taskManager") {
                    Task(priority: .userInitiated) {
                        do {
                            try await Wine.taskManager(bottle: bottle)
                        } catch {
                            print("Failed to launch task manager")
                        }
                    }
                }

                Button("button.openLogs") {
                    NSWorkspace.shared.open(Wine.logsFolder)
                }

                Button("button.openLatestLog") {
                    if let url = Wine.latestLogFileURL() {
                        NSWorkspace.shared.open(url)
                    } else {
                        NSWorkspace.shared.open(Wine.logsFolder)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("tab.config")
        .onAppear {
            winVersionLoadingState = .success

            loadBuildName()

            Task(priority: .userInitiated) {
                do {
                    retinaMode = try await Wine.retinaMode(bottle: bottle)
                    retinaModeLoadingState = .success
                } catch {
                    print(error)
                    retinaModeLoadingState = .failed
                }
            }
            Task(priority: .userInitiated) {
                do {
                    dpiConfig = try await Wine.dpiResolution(bottle: bottle) ?? 0
                    dpiConfigLoadingState = .success
                } catch {
                    print(error)
                    // If DPI has not yet been edited, there will be no registry entry
                    dpiConfigLoadingState = .success
                }
            }
            proxyEnabled = bottle.settings.proxyEnabled
            proxyHost = bottle.settings.proxyHost
            proxyPort = bottle.settings.proxyPort

            Task(priority: .userInitiated) {
                let version = try? await Wine.wineVersion(bottle: bottle)
                await MainActor.run {
                    runtimeWineVersion = version
                }
            }
        }
        .onChange(of: bottle.settings.windowsVersion) { _, newValue in
            if winVersionLoadingState == .success {
                winVersionLoadingState = .loading
                buildVersionLoadingState = .loading
                Task(priority: .userInitiated) {
                    do {
                        try await Wine.changeWinVersion(bottle: bottle, win: newValue)
                        winVersionLoadingState = .success
                        bottle.settings.windowsVersion = newValue
                        loadBuildName()
                    } catch {
                        print(error)
                        winVersionLoadingState = .failed
                    }
                }
            }
        }
        .onChange(of: dpiConfig) {
            if dpiConfigLoadingState == .success {
                Task(priority: .userInitiated) {
                    dpiConfigLoadingState = .modifying
                    do {
                        try await Wine.changeDpiResolution(bottle: bottle, dpi: dpiConfig)
                        dpiConfigLoadingState = .success
                    } catch {
                        print(error)
                        dpiConfigLoadingState = .failed
                    }
                }
            }
        }
    }

    func loadBuildName() {
        Task(priority: .userInitiated) {
            do {
                if let buildVersionString = try await Wine.buildVersion(bottle: bottle) {
                    buildVersion = Int(buildVersionString) ?? 0
                } else {
                    buildVersion = 0
                }

                buildVersionLoadingState = .success
            } catch {
                print(error)
                buildVersionLoadingState = .failed
            }
        }
    }

    func applyProxySettings() {
        normalizeProxyFields()
        bottle.settings.proxyEnabled = proxyEnabled
        bottle.settings.proxyHost = proxyHost
        bottle.settings.proxyPort = proxyPort
        proxyLoadingState = .modifying
        Task(priority: .userInitiated) {
            do {
                try await WineProxySettings.applyIfNeeded(bottle: bottle)
                await MainActor.run {
                    proxyLoadingState = .success
                    proxyHost = bottle.settings.proxyHost
                    proxyPort = bottle.settings.proxyPort
                }
            } catch {
                print(error)
                await MainActor.run {
                    proxyLoadingState = .failed
                }
            }
        }
    }

    private func normalizeProxyFields() {
        // If user pastes "host:port" into host field, split it.
        let host = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard port.isEmpty else { return }

        let parts = host.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return } // avoid IPv6 / URLs

        proxyHost = String(parts[0])
        proxyPort = String(parts[1])
    }

    private func updatePinnedGameExecutable(oldURL: URL?, newURL: URL) {
        // The bottle home screen renders pins via `bottle.pinnedPrograms`, which is derived from `bottle.programs`.
        // Selecting a new executable updates settings/pins, but the programs list is only refreshed on appear.
        // Refresh it here so the icon updates immediately when returning.

        if let oldURL, oldURL != newURL, let idx = bottle.settings.pins.firstIndex(where: { $0.url == oldURL }) {
            // Avoid creating duplicate pins for the new executable.
            if bottle.settings.pins.contains(where: { $0.url == newURL }) {
                bottle.settings.pins.remove(at: idx)
            } else {
                let existingName = bottle.settings.pins[idx].name
                bottle.settings.pins[idx] = PinnedProgram(name: existingName, url: newURL)
            }
        } else if !bottle.settings.pins.contains(where: { $0.url == newURL }) {
            bottle.settings.pins.append(PinnedProgram(name: newURL.deletingPathExtension().lastPathComponent, url: newURL))
        }

        bottle.updateInstalledPrograms()
    }
}

struct DPIConfigSheetView: View {
    @Binding var dpiConfig: Int
    @Binding var isRetinaMode: Bool
    @Binding var presented: Bool
    @State var stagedChanges: Float
    @FocusState var textFocused: Bool

    init(dpiConfig: Binding<Int>, isRetinaMode: Binding<Bool>, presented: Binding<Bool>) {
        self._dpiConfig = dpiConfig
        self._isRetinaMode = isRetinaMode
        self._presented = presented
        self.stagedChanges = Float(dpiConfig.wrappedValue)
    }

    var body: some View {
        VStack {
            HStack {
                Text("configDpi.title")
                    .fontWeight(.bold)
                Spacer()
            }
            Divider()
            GroupBox(label: Label("configDpi.preview", systemImage: "text.magnifyingglass")) {
                VStack {
                    HStack {
                        Text("configDpi.previewText")
                            .padding(16)
                            .font(.system(size:
                                (10 * CGFloat(stagedChanges)) / 72 *
                                          (isRetinaMode ? 0.5 : 1)
                            ))
                        Spacer()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 80)
            }
            HStack {
                Slider(value: $stagedChanges, in: 96...480, step: 24, onEditingChanged: { _ in
                    textFocused = false
                })
                TextField(String(), value: $stagedChanges, format: .number)
                    .frame(width: 40)
                    .focused($textFocused)
                Text("configDpi.dpi")
            }
            Spacer()
            HStack {
                Spacer()
                Button("create.cancel") {
                    presented = false
                }
                .keyboardShortcut(.cancelAction)
                Button("button.ok") {
                    dpiConfig = Int(stagedChanges)
                    presented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: ViewWidth.medium, height: 240)
    }
}

struct SettingItemView<Content: View>: View {
    let title: String.LocalizationValue
    let loadingState: LoadingState
    @ViewBuilder var content: () -> Content

    @Namespace private var viewId
    @Namespace private var progressViewId

    var body: some View {
        HStack {
            Text(String(localized: title))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                switch loadingState {
                case .loading, .modifying:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .matchedGeometryEffect(id: progressViewId, in: viewId)
                case .success:
                    content()
                        .labelsHidden()
                        .disabled(loadingState != .success)
                case .failed:
                    Text("config.notAvailable")
                        .font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                }
            }.animation(.default, value: loadingState)
        }
    }
}
