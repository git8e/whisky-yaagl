//
//  PinView.swift
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

/// Finder icon-view metrics used by the pinned-program grid.
enum PinLayout {
    static let iconSize: CGFloat = 64
    static let cellWidth: CGFloat = 113
    static let cellHeight: CGFloat = 112
    static let labelWidth: CGFloat = 109
    static let rowSpacing: CGFloat = 8
    static let labelFont: Font = .system(size: 12)
}

struct PinView: View {
    @ObservedObject var bottle: Bottle
    @ObservedObject var program: Program
    @State var pin: PinnedProgram
    @Binding var path: NavigationPath

    @State private var image: Image?
    @State private var showRenameSheet = false
    @State private var name: String = ""
    @State private var opening: Bool = false

    private var isStarting: Bool {
        program.isStarting
    }

    var body: some View {
        VStack(spacing: PinLayout.rowSpacing) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = image {
                        image
                            .resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                    }
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: PinLayout.iconSize, height: PinLayout.iconSize)
                .scaleEffect(opening ? 1.8 : 1)
                .opacity(opening ? 0 : 1)

                if isStarting {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.black.opacity(0.18))
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial.opacity(0.78))
                        ProgressView()
                            .controlSize(.large)
                            .scaleEffect(1.24)
                    }
                    .frame(width: PinLayout.iconSize, height: PinLayout.iconSize)
                } else {
                    Image(systemName: "play.fill")
                        .resizable()
                        .foregroundColor(.green)
                        .frame(width: 20, height: 20)
                        .padding(.top, 2)
                        .padding(.trailing, 2)
                }
            }
            .frame(width: PinLayout.iconSize, height: PinLayout.iconSize)
            Text(name)
                .font(PinLayout.labelFont)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: PinLayout.labelWidth)
                .help(name)
        }
        .frame(width: PinLayout.cellWidth, height: PinLayout.cellHeight, alignment: .top)
        .contextMenu {
            ProgramMenuView(program: program, path: $path)

            Button("button.rename", systemImage: "pencil.line") {
                showRenameSheet.toggle()
            }
            .labelStyle(.titleAndIcon)
            Button("button.showInFinder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([program.url])
            }
            .labelStyle(.titleAndIcon)
        }
        .onTapGesture(count: 2) {
            guard !program.isLaunching else { return }
            runProgram()
        }
        .allowsHitTesting(!program.isLaunching)
        .sheet(isPresented: $showRenameSheet) {
            RenameView("rename.pin.title", name: name) { newName in
                name = newName
            }
        }
        .task {
            name = pin.name
            guard let peFile = program.peFile else { return }
            let task = Task.detached {
                guard let image = peFile.bestIcon() else { return nil as Image? }
                return Image(nsImage: image)
            }
            self.image = await task.value
        }
        .task {
            // Start wineserver/winedevice while the user is still choosing a
            // pin. The actual game process then starts in about a second
            // instead of paying Wine's cold-start cost after the click.
            await Wine.prewarm(bottle: bottle)
        }
        .onChange(of: name) {
            guard let currentURL = pin.url,
                  let index = bottle.settings.pins.firstIndex(where: { pin in
                      guard let pinURL = pin.url else { return false }
                      return pinURL.isSameFile(as: currentURL)
                  }) else {
                return
            }
            bottle.settings.pins[index].name = name
        }
        .onChange(of: program.isStarting) { _, newValue in
            if !newValue {
                opening = false
            }
        }
    }

    func runProgram() {
        guard !opening else { return }
        withAnimation(.easeIn(duration: 0.25)) {
            opening = true
        }

        program.run()
    }
}
