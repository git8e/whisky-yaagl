//
//  Main.swift
//  WhiskyCmd
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
import AppKit
import CoreGraphics
import WhiskyKit
import SwiftyTextTable
import Progress
import SemanticVersion
import ArgumentParser

@main
struct Whisky: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A CLI interface for Whisky.",
        subcommands: [List.self,
                      Create.self,
                      Add.self,
//                      Export.self,
                      Delete.self,
                      Remove.self,
                      Run.self,
                      Shellenv.self,
                      BounceWatch.self
                      /*Install.self,
                      Uninstall.self*/])
}

extension Whisky {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List existing bottles.")

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let nameCol = TextTableColumn(header: "Name")
            let winVerCol = TextTableColumn(header: "Windows Version")
            let pathCol = TextTableColumn(header: "Path")

            var table = TextTable(columns: [nameCol, winVerCol, pathCol])
            for bottle in bottles {
                table.addRow(values: [bottle.settings.name,
                                      bottle.settings.windowsVersion.pretty(),
                                      bottle.url.prettyPath()])
            }

            print(table.render())
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new bottle.")

        @Argument var name: String

        mutating func run() throws {
            let bottleURL = BottleData.defaultBottleDir.appending(path: UUID().uuidString)

            do {
                try FileManager.default.createDirectory(atPath: bottleURL.path(percentEncoded: false),
                                                        withIntermediateDirectories: true)
                let bottle = Bottle(bottleUrl: bottleURL, inFlight: true)
                // Should allow customisation
                bottle.settings.windowsVersion = .win10
                bottle.settings.name = name
//                try await Wine.changeWinVersion(bottle: bottle, win: winVersion)
//                let wineVer = try await Wine.wineVersion()
                bottle.settings.wineVersion = SemanticVersion(0, 0, 0)

                var bottlesList = BottleData()
                bottlesList.paths.append(bottleURL)
                print("Created new bottle \"\(name)\".")
            } catch {
                throw ValidationError("\(error)")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add an existing bottle.")

        @Argument var path: String

        mutating func run() throws {
            // Should be sanitised
            let bottleURL = URL(filePath: path)
            let settings = try BottleSettings.decode(from: bottleURL)
            var bottlesList = BottleData()
            bottlesList.paths.append(bottleURL)
            print("Bottle \"\(settings.name)\" added.")
        }
    }

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Export an existing bottle.")

        mutating func run() throws {
//            print("Create a bottle")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete an existing bottle from disk.")

        @Argument var name: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            // Should ask for confirmation
            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove = bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                do {
                    try FileManager.default.removeItem(at: bottleToRemove.url)
                    print("Deleted \"\(name)\".")
                } catch {
                    print(error)
                }
            } else {
                throw ValidationError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove an existing bottle from Whisky.",
                                                        discussion: "This will not remove the bottle from disk.")

        @Argument var name: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            let bottleToRemove = bottles.first(where: { $0.settings.name == name })
            if let bottleToRemove = bottleToRemove {
                bottlesList.paths.removeAll(where: { $0 == bottleToRemove.url })
                print("Removed \"\(name)\".")
            } else {
                throw ValidationError("No bottle called \"\(name)\" found.")
            }
        }
    }

    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run a program with Whisky.")

        @Argument var bottleName: String
        @Argument var path: String
        @Argument var args: [String] = []

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            let url = URL(fileURLWithPath: path)
            let program = Program(url: url, bottle: bottle)
            program.runInTerminal()
        }
    }

    struct Shellenv: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Prints export statements for a Bottle for eval.")

        @Argument var bottleName: String

        mutating func run() throws {
            var bottlesList = BottleData()
            let bottles = bottlesList.loadBottles()

            guard let bottle = bottles.first(where: { $0.settings.name == bottleName }) else {
                throw ValidationError("A bottle with that name doesn't exist.")
            }

            let envCmd = Wine.generateTerminalEnvironmentCommand(bottle: bottle)
            print(envCmd)

        }
    }

    /// Keeps the Dock tile asking for attention until the launch finishes.
    ///
    /// A single `requestUserAttention(.criticalRequest)` is often shortened by
    /// macOS (and depends on the user's Dock bounce preference). Re-request
    /// after each short interval so the animation continues for the whole
    /// startup instead of stopping after the first two bounces.
    private final class BounceWatcher: NSObject, NSApplicationDelegate {
        private var timer: Timer?
        private var attentionRequest: Int?

        func applicationDidFinishLaunching(_ notification: Notification) {
            requestAttention()
            let timer = Timer(timeInterval: 0.9, repeats: true) { [weak self] _ in
                self?.requestAttention()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        private func requestAttention() {
            if let attentionRequest {
                NSApp.cancelUserAttentionRequest(attentionRequest)
            }
            let request = NSApp.requestUserAttention(.criticalRequest)
            attentionRequest = request == 0 ? nil : request
        }
    }

    /// Internal helper used by the app's generated launch beacons.
    /// It gives the process a regular Dock tile, asks the Dock to bounce it,
    /// and exits when the first Wine window appears.
    struct BounceWatch: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bounce-watch",
            abstract: "Internal helper that bounces a launch icon until Wine shows a window."
        )

        @Argument var timeout: Double = 45
        @Argument var baseline: String = ""

        mutating func run() throws {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
                app.applicationIconImage = NSImage(contentsOf: iconURL)
            }
            let watcher = BounceWatcher()
            app.delegate = watcher

            let baselineIDs = Set(
                baseline
                    .split(separator: ",")
                    .compactMap { CGWindowID(String($0)) }
            )
            let snapshot = WineWindowSnapshot.Snapshot(windowIDs: baselineIDs)
            let watchTimeout = timeout

            Task {
                _ = await WineWindowSnapshot.waitForNewWindow(
                    since: snapshot,
                    timeout: watchTimeout,
                    includeNonWine: true
                )
                await MainActor.run {
                    NSApp.terminate(nil)
                }
            }

            app.run()
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install WhiskyWine.")

        mutating func run() throws {

        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Uninstall WhiskyWine.")

        @Flag(name: [.long, .short], help: "Uninstall WhiskyWine") var whiskyWine = false

        mutating func run() throws {

        }
    }
}
