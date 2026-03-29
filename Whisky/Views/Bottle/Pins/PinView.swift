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

struct PinView: View {
    @ObservedObject var bottle: Bottle
    @ObservedObject var program: Program
    @State var pin: PinnedProgram
    @Binding var path: NavigationPath

    @State private var image: Image?
    @State private var showRenameSheet = false
    @State private var name: String = ""
    @State private var opening: Bool = false

    private var isLaunching: Bool {
        program.isLaunching
    }

    var body: some View {
        VStack {
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
                .frame(width: 45, height: 45)
                .scaleEffect(opening ? 2 : 1)
                .opacity(opening ? 0 : 1)

                if isLaunching {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.black.opacity(0.18))
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(0.78))
                        ProgressView()
                            .controlSize(.large)
                            .scaleEffect(1.18)
                    }
                    .frame(width: 46, height: 46)
                } else {
                    Image(systemName: "play.fill")
                        .resizable()
                        .foregroundColor(.green)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)
                        .padding(.trailing, 2)
                }
            }
            .frame(width: 45, height: 45)
            Color.clear
                .frame(height: 8)
            Text(name)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(name)
        }
        .frame(width: 90, height: 90)
        .padding(10)
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
            guard !isLaunching else { return }
            runProgram()
        }
        .allowsHitTesting(!isLaunching)
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
        .onChange(of: name) {
            if let index = bottle.settings.pins.firstIndex(where: {
                return $0.url == pin.url
            }) {
                bottle.settings.pins[index].name = name
            }
        }
        .onChange(of: program.isLaunching) { _, newValue in
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
