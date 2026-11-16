//
//  ContentView.swift
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

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit
import SemanticVersion

struct ContentView: View {
    @AppStorage("selectedBottleURL") private var selectedBottleURL: URL?
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool

    @State private var selected: URL?
    @State private var showBottleCreation: Bool = false
    @State private var bottlesLoaded: Bool = false
    @State private var showBottleSelection: Bool = false
    @State private var newlyCreatedBottleURL: URL?
    @State private var openedFileURL: URL?
    @State private var triggerRefresh: Bool = false
    @State private var refreshAnimation: Angle = .degrees(0)

    @State private var bottleFilter = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if KeyMacroToolbarCoordinator.shared.isActive {
                        KeyMacroToolbarCoordinator.shared.requestNewMacro()
                    } else {
                        showBottleCreation.toggle()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("button.createBottle")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bottleVM.loadBottles()
                    if let bottle = bottleVM.bottles.first(where: { $0.url == selected }) {
                        bottle.refreshProgramsAndPinsFromDisk()
                    }
                    triggerRefresh.toggle()
                    withAnimation(.default) {
                        refreshAnimation = .degrees(360)
                    } completion: {
                        refreshAnimation = .degrees(0)
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .help("button.refresh")
                        .rotationEffect(refreshAnimation)
                }
            }
        }
        .background(
            WindowConfigurator()
                .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showBottleCreation) {
            BottleCreationView(newlyCreatedBottleURL: $newlyCreatedBottleURL)
        }
        .sheet(isPresented: $showSetup) {
            SetupView(showSetup: $showSetup, firstTime: false)
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: selected,
                         bottles: bottleVM.bottles)
        }
        .onChange(of: selected) {
            selectedBottleURL = selected
            KeyMacroToolbarCoordinator.shared.deactivate()
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            await WineRuntimes.refreshCatalog(forceRemote: false)
            bottleVM.loadBottles()
            bottlesLoaded = true

            if !bottleVM.bottles.isEmpty || bottleVM.countActive() != 0 {
                if let bottle = bottleVM.bottles.first(where: { $0.url == selectedBottleURL && $0.isAvailable }) {
                    selected = bottle.url
                } else {
                    selected = bottleVM.bottles[0].url
                }
            }

            let hasDxmtRuntime = WineRuntimes.all.contains { runtime in
                runtime.id != WineRuntimes.whiskyDefaultId
                    && runtime.renderBackend == .dxmt
                    && WineRuntimeManager.isInstalled(runtimeId: runtime.id)
            }
            if !hasDxmtRuntime {
                showSetup = true
            }
        }
    }

    var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                Section {
                    ForEach(filteredBottles) { bottle in
                        Group {
                            if bottle.inFlight {
                                HStack {
                                    Text(bottle.settings.name)
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                                .opacity(0.5)
                            } else {
                                BottleListEntry(bottle: bottle, selected: $selected, refresh: $triggerRefresh)
                                    .selectionDisabled(!bottle.isAvailable)
                            }
                        }
                        .id(bottle.url)
                        .tag(bottle.url)
                    }
                }
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: bottleFilter)
            .listStyle(.sidebar)
            .searchable(text: $bottleFilter, placement: .sidebar)
            .onChange(of: newlyCreatedBottleURL) { _, _ in
                selectNewBottle(using: proxy)
            }
            .onChange(of: showBottleCreation) { _, _ in
                selectNewBottle(using: proxy)
            }
        }
    }

    private func selectNewBottle(using proxy: ScrollViewProxy) {
        guard !showBottleCreation, let url = newlyCreatedBottleURL else { return }
        newlyCreatedBottleURL = nil

        // Clear the previous selection first. Selecting the new bottle while
        // the old one is still selected can leave both rows highlighted on
        // macOS.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selected = nil
        }

        DispatchQueue.main.async {
            withAnimation {
                selected = url
                proxy.scrollTo(url, anchor: .center)
            }
        }
    }

    @ViewBuilder
    var detail: some View {
        if let bottle = selected {
            if let bottle = bottleVM.bottles.first(where: { $0.url == bottle }) {
                BottleView(bottle: bottle)
                    .disabled(bottle.inFlight)
                    .id(bottle.url)
            }
        } else {
            if (bottleVM.bottles.isEmpty || bottleVM.countActive() == 0) && bottlesLoaded {
                VStack {
                    Text("main.createFirst")
                    Button {
                        showBottleCreation.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("button.createBottle")
                        }
                        .padding(6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }
        }
    }

    var filteredBottles: [Bottle] {
        if bottleFilter.isEmpty {
            bottleVM.bottles
                .sorted()
        } else {
            bottleVM.bottles
                .filter { $0.settings.name.localizedCaseInsensitiveContains(bottleFilter) }
                .sorted()
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    private static let resetKey = "didResetWindowFor017"

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            guard !UserDefaults.standard.bool(forKey: Self.resetKey) else { return }

            let targetSize = NSSize(width: 1280, height: 720)
            var frame = window.frame
            // Keep the top edge in place while changing the size.
            frame.origin.y -= targetSize.height - frame.height
            frame.size = targetSize
            if let screen = window.screen {
                frame = window.constrainFrameRect(frame, to: screen)
            }
            window.setFrame(frame, display: true)
            UserDefaults.standard.set(true, forKey: Self.resetKey)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
