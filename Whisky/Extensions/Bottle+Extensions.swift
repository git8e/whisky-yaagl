//
//  Bottle+Extensions.swift
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
import AppKit
import WhiskyKit
import os.log

extension Bottle {
    @MainActor
    func duplicate() {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            let parent = url.deletingLastPathComponent()
            let newBottleURL = parent.appending(path: UUID().uuidString)

            try FileCopy.copyItem(at: url, to: newBottleURL)

            // Clear transient per-launch state.
            let hk4ePatchState = newBottleURL
                .appendingPathComponent("HK4e", isDirectory: true)
                .appending(path: "patch-state.json", directoryHint: .notDirectory)
            try? FileManager.default.removeItem(at: hk4ePatchState)

            let hkrpgPatchState = newBottleURL
                .appendingPathComponent("HKRPG", isDirectory: true)
                .appending(path: "patch-state.json", directoryHint: .notDirectory)
            try? FileManager.default.removeItem(at: hkrpgPatchState)

            // Fix URLs inside metadata (pins, blocklist, stored executable paths).
            let newBottle = Bottle(bottleUrl: newBottleURL, inFlight: true)
            let oldBottleURL = url

            for index in 0..<newBottle.settings.pins.count {
                let pin = newBottle.settings.pins[index]
                if let pinURL = pin.url {
                    newBottle.settings.pins[index].url = pinURL.updateParentBottle(old: oldBottleURL, new: newBottleURL)
                }
            }
            for index in 0..<newBottle.settings.blocklist.count {
                let blockedURL = newBottle.settings.blocklist[index]
                newBottle.settings.blocklist[index] = blockedURL.updateParentBottle(old: oldBottleURL, new: newBottleURL)
            }
            if let exe = newBottle.settings.hk4eGameExecutableURL {
                newBottle.settings.hk4eGameExecutableURL = exe.updateParentBottle(old: oldBottleURL, new: newBottleURL)
            }
            if let exe = newBottle.settings.napGameExecutableURL {
                newBottle.settings.napGameExecutableURL = exe.updateParentBottle(old: oldBottleURL, new: newBottleURL)
            }
            if let exe = newBottle.settings.hkrpgGameExecutableURL {
                newBottle.settings.hkrpgGameExecutableURL = exe.updateParentBottle(old: oldBottleURL, new: newBottleURL)
            }

            // Give it a new display name.
            newBottle.settings.name = String(format: String(localized: "bottle.duplicate.name"), newBottle.settings.name)

            BottleVM.shared.bottlesList.paths.append(newBottleURL)
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to duplicate bottle: \(error)")
        }
    }

    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() {
        let whiskyCmdURL = Bundle.main.url(forResource: "WhiskyCmd", withExtension: nil)
        if let whiskyCmdURL = whiskyCmdURL {
            let whiskyCmd = whiskyCmdURL.path(percentEncoded: false)
            let cmd = "eval \\\"$(\\\"\(whiskyCmd)\\\" shellenv \\\"\(settings.name)\\\")\\\""

            let script = """
            tell application "Terminal"
            activate
            do script "\(cmd)"
            end tell
            """

            Task.detached(priority: .userInitiated) {
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else { return }
                appleScript.executeAndReturnError(&error)

                if let error = error {
                    Logger.wineKit.error("Failed to run terminal script \(error)")
                    guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                    await self.showRunError(message: String(describing: description))
                }
            }
        }
    }

    func openTaskManager() {
        Task.detached(priority: .userInitiated) {
            do {
                try await Wine.taskManager(bottle: self)
            } catch {
                Logger.wineKit.error("Failed to open task manager: \(error)")
                await self.showRunError(message: String(describing: error.localizedDescription))
            }
        }
    }

    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        getStartMenuShortcuts().map(\.program)
    }

    private func getStartMenuShortcuts() -> [ShortcutProgram] {
        let globalStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "ProgramData")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        let userStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        return getShortcutPrograms(in: [globalStartMenu, userStartMenu], removeShortcuts: true)
    }

    @discardableResult
    func getDesktopPrograms() -> [Program] {
        getDesktopShortcuts().map(\.program)
    }

    private func getDesktopShortcuts() -> [ShortcutProgram] {
        let usersFolder = url
            .appending(path: "drive_c")
            .appending(path: "users")

        let userFolders = (try? FileManager.default.contentsOfDirectory(
            at: usersFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let desktopFolders = userFolders.compactMap { userFolder -> URL? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: userFolder.path(percentEncoded: false),
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                return nil
            }
            return userFolder.appending(path: "Desktop", directoryHint: .isDirectory)
        }

        return getShortcutPrograms(in: desktopFolders, removeShortcuts: false)
    }

    private struct ShortcutProgram {
        var program: Program
        var name: String
    }

    private func getShortcutPrograms(in folders: [URL], removeShortcuts: Bool) -> [ShortcutProgram] {
        var shortcutPrograms: [ShortcutProgram] = []
        var linkURLs: [URL] = []

        for folder in folders {
            let enumerator = FileManager.default.enumerator(at: folder,
                                                            includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "lnk" {
                    linkURLs.append(url)
                }
            }
        }

        linkURLs.sort(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })

        for link in linkURLs {
            do {
                if let program = ShellLinkHeader.getProgram(url: link,
                                                            handle: try FileHandle(forReadingFrom: link),
                                                            bottle: self) {
                    if !shortcutPrograms.contains(where: { $0.program.url == program.url }) {
                        shortcutPrograms.append(ShortcutProgram(
                            program: program,
                            name: link.deletingPathExtension().lastPathComponent
                        ))
                        if removeShortcuts {
                            try FileManager.default.removeItem(at: link)
                        }
                    }
                }
            } catch {
                print(error)
            }
        }

        return shortcutPrograms
    }

    func updateInstalledPrograms() {
        let driveC = url.appending(path: "drive_c")
        var programs: [Program] = []
        var foundURLS: Set<URL> = []

        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath && url.pathExtension == "exe" else { continue }
                guard !settings.blocklist.contains(url) else { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Add missing programs from pins
        for pin in settings.pins {
            guard let url = pin.url else { continue }
            guard !foundURLS.contains(url) else { continue }
            programs.append(Program(url: url, bottle: self))
        }

        self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Refreshes `programs` and imports new Start Menu/Desktop shortcuts into pins.
    ///
    /// Some installers only become discoverable via Start Menu/Desktop `.lnk` files, which are
    /// processed here so newly installed apps can appear without restarting the app.
    @MainActor
    func refreshProgramsAndPinsFromDisk() {
        updateInstalledPrograms()

        let shortcutPrograms = getStartMenuShortcuts().map { (shortcut: $0, ignoresBlocklist: false) }
            + getDesktopShortcuts().map { (shortcut: $0, ignoresBlocklist: true) }
        for shortcutProgram in shortcutPrograms {
            // Match by case-insensitive path because URL equality is case-sensitive.
            let existing = programs.first(where: {
                $0.url.path().caseInsensitiveCompare(shortcutProgram.shortcut.program.url.path()) == .orderedSame
            })

            let program: Program
            if let existing {
                program = existing
            } else {
                // Shortcuts should surface apps even when their target lives outside Program Files.
                guard shortcutProgram.ignoresBlocklist || !settings.blocklist.contains(shortcutProgram.shortcut.program.url) else {
                    continue
                }
                programs.append(shortcutProgram.shortcut.program)
                program = shortcutProgram.shortcut.program
            }

            // Ensure a pin exists even if path casing differs.
            if let pinIndex = settings.pins.firstIndex(where: { pin in
                guard let pinURL = pin.url else { return false }
                return pinURL.path().caseInsensitiveCompare(program.url.path()) == .orderedSame
            }) {
                let executableName = program.url.deletingPathExtension().lastPathComponent
                if settings.pins[pinIndex].name == executableName || settings.pins[pinIndex].name == program.name {
                    settings.pins[pinIndex].name = shortcutProgram.shortcut.name
                }
            } else {
                settings.pins.append(PinnedProgram(
                    name: shortcutProgram.shortcut.name,
                    url: program.url
                ))
            }

            if !program.pinned {
                program.pinned = true
            }
        }

        // Re-sort after adding Start Menu programs.
        programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @MainActor
    func move(destination: URL) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
                for index in 0..<bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let url = pin.url {
                        bottle.settings.pins[index].url = url.updateParentBottle(old: url,
                                                                                 new: destination)
                    }
                }

                for index in 0..<bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(old: url,
                                                                                     new: destination)
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to move bottle")
        }
    }

    func exportAsArchive(destination: URL) {
        do {
            try Tar.tar(folder: url, toURL: destination)
        } catch {
            print("Failed to export bottle")
        }
    }

    @MainActor
    func remove(delete: Bool) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            if delete {
                try FileManager.default.removeItem(at: url)
            }

            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths.remove(at: path)
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to remove bottle")
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
