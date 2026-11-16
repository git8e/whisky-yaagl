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

        let usersFolder = url
            .appending(path: "drive_c")
            .appending(path: "users")

        let userFolders = (try? FileManager.default.contentsOfDirectory(
            at: usersFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let userStartMenus = userFolders.compactMap { userFolder -> URL? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: userFolder.path(percentEncoded: false),
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                return nil
            }
            return userFolder.appending(path: "AppData/Roaming/Microsoft/Windows/Start Menu",
                                        directoryHint: .isDirectory)
        }

        return getShortcutPrograms(in: [globalStartMenu] + userStartMenus, removeShortcuts: true)
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
                    let shortcutName = link.deletingPathExtension().lastPathComponent
                    guard !isUninstallerShortcut(name: shortcutName, programURL: program.url) else {
                        continue
                    }
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
        // Uninstallers should stay available from Installed Programs but not
        // clutter the bottle home screen (their icons are often blank).
        settings.pins.removeAll { pin in
            guard let url = pin.url else { return false }
            return Program.isUninstallerExecutable(url)
        }

        updateInstalledPrograms()

        let shortcutPrograms = getStartMenuShortcuts().map { (shortcut: $0, ignoresBlocklist: false) }
            + getDesktopShortcuts().map { (shortcut: $0, ignoresBlocklist: true) }

        // Installers may create several shortcuts for one executable. HoYoPlay,
        // for example, creates one shortcut per game that all point at its
        // launcher, so grouping avoids naming the pin after an arbitrary game.
        var groups: [String: (program: Program, names: [String], ignoresBlocklist: Bool)] = [:]
        for entry in shortcutPrograms {
            guard !isUninstallerShortcut(name: entry.shortcut.name,
                                         programURL: entry.shortcut.program.url) else {
                continue
            }
            let key = entry.shortcut.program.url.path().lowercased()
            if var group = groups[key] {
                group.names.append(entry.shortcut.name)
                group.ignoresBlocklist = group.ignoresBlocklist || entry.ignoresBlocklist
                groups[key] = group
            } else {
                groups[key] = (program: entry.shortcut.program,
                               names: [entry.shortcut.name],
                               ignoresBlocklist: entry.ignoresBlocklist)
            }
        }

        for group in groups.values.sorted(by: { $0.program.url.path() < $1.program.url.path() }) {
            // Match by case-insensitive path because URL equality is case-sensitive.
            let existing = programs.first(where: {
                $0.url.path().caseInsensitiveCompare(group.program.url.path()) == .orderedSame
            })

            let program: Program
            if let existing {
                program = existing
            } else {
                // Shortcuts should surface apps even when their target lives outside Program Files.
                guard group.ignoresBlocklist || !settings.blocklist.contains(group.program.url) else {
                    continue
                }
                programs.append(group.program)
                program = group.program
            }

            let name = preferredShortcutName(for: program.url, candidates: group.names)
            let automaticNames = Set(group.names + [
                program.name,
                program.url.deletingPathExtension().lastPathComponent
            ])

            // Ensure a pin exists even if path casing differs.
            if let pinIndex = settings.pins.firstIndex(where: { pin in
                guard let pinURL = pin.url else { return false }
                return pinURL.path().caseInsensitiveCompare(program.url.path()) == .orderedSame
            }) {
                // Only update names that look auto-generated; keep user renames.
                if automaticNames.contains(settings.pins[pinIndex].name),
                   settings.pins[pinIndex].name != name {
                    settings.pins[pinIndex].name = name
                }
            } else {
                settings.pins.append(PinnedProgram(
                    name: name,
                    url: program.url
                ))
            }

            if !program.pinned {
                program.pinned = true
            }
        }

        // Re-sort after adding Start Menu programs.
        programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }

        autoAssociateHoYoPlayGameIfNeeded()
    }

    /// HoYoPlay records each installed game's path in the prefix registry. If
    /// the user did not pick a game executable during bottle creation, adopt
    /// the matching game and pin it so the home screen launches it directly
    /// (with this bottle's patches) instead of opening the launcher first.
    @MainActor
    func autoAssociateHoYoPlayGameIfNeeded() {
        guard settings.hk4eGameExecutableURL == nil
            || settings.napGameExecutableURL == nil
            || settings.hkrpgGameExecutableURL == nil else {
            return
        }

        for install in hoyoPlayRegistryGames() {
            let kind = install.gameKind
            guard kind.matches(settings.gamePreset) else { continue }
            guard let executableURL = hoyoPlayExecutable(for: install),
                  FileManager.default.fileExists(atPath: executableURL.path(percentEncoded: false)) else {
                continue
            }

            switch kind {
            case .hk4e:
                guard settings.hk4eGameExecutableURL == nil else { continue }
                settings.hk4eGameExecutableURL = executableURL
                settings.hk4eRegion = install.isChina ? .cn : .os
            case .nap:
                guard settings.napGameExecutableURL == nil else { continue }
                settings.napGameExecutableURL = executableURL
                settings.napRegion = install.isChina ? .cn : .os
            case .hkrpg:
                guard settings.hkrpgGameExecutableURL == nil else { continue }
                settings.hkrpgGameExecutableURL = executableURL
                settings.hkrpgRegion = install.isChina ? .cn : .os
            }

            pinHoYoPlayGame(executableURL, displayName: install.displayName)
        }
    }

    private enum HoYoPlayGameKind {
        case hk4e
        case nap
        case hkrpg

        func matches(_ preset: BottleGamePreset) -> Bool {
            switch (self, preset) {
            case (.hk4e, .hk4e), (.nap, .nap), (.hkrpg, .hkrpg):
                return true
            default:
                return false
            }
        }
    }

    private struct HoYoPlayRegistryGame {
        let business: String
        let installPath: String

        var gameKind: HoYoPlayGameKind {
            if business.hasPrefix("hk4e") { return .hk4e }
            if business.hasPrefix("nap") { return .nap }
            return .hkrpg
        }

        var isChina: Bool {
            business.hasSuffix("_cn")
        }

        var displayName: String {
            switch gameKind {
            case .hk4e:
                return "Genshin Impact"
            case .nap:
                return "Zenless Zone Zero"
            case .hkrpg:
                return "Honkai: Star Rail"
            }
        }

        var executableNames: [String] {
            switch gameKind {
            case .hk4e:
                return ["genshinimpact.exe", "yuanshen.exe"]
            case .nap:
                return ["zenlesszonezero.exe"]
            case .hkrpg:
                return ["starrail.exe"]
            }
        }
    }

    private func hoyoPlayRegistryGames() -> [HoYoPlayRegistryGame] {
        let registryURL = url.appending(path: "user.reg")
        guard let data = try? Data(contentsOf: registryURL),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }

        let knownBusiness = [
            "hk4e_global", "hk4e_cn",
            "nap_global", "nap_cn",
            "hkrpg_global", "hkrpg_cn"
        ]
        var games: [HoYoPlayRegistryGame] = []
        var section = ""
        var business: String?
        var installPath: String?

        func flush() {
            if let business, let installPath, !installPath.isEmpty {
                games.append(HoYoPlayRegistryGame(business: business, installPath: installPath))
            }
            business = nil
            installPath = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                section = unescapeRegistry(String(line.dropFirst().dropLast()))
                if section.contains("\\Cognosphere\\HYP\\1_0\\"),
                   let last = section.split(separator: "\\").last.map(String.init),
                   knownBusiness.contains(last) {
                    business = last
                }
                continue
            }

            guard business != nil else { continue }
            if line.hasPrefix("\"GameBiz\"") {
                if let value = registryValue(from: line), knownBusiness.contains(value) {
                    business = value
                }
            } else if line.hasPrefix("\"GameInstallPath\"") {
                installPath = registryValue(from: line)
            }
        }
        flush()

        return games
    }

    private func registryValue(from line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        var value = String(line[line.index(after: equals)...])
        value = value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return unescapeRegistry(value)
    }

    private func unescapeRegistry(_ value: String) -> String {
        value.replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func hoyoPlayExecutable(for install: HoYoPlayRegistryGame) -> URL? {
        guard let installURL = localURL(forWinePath: install.installPath) else { return nil }
        let fileManager = FileManager.default

        for name in install.executableNames {
            let direct = installURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: direct.path(percentEncoded: false)) {
                return direct
            }
        }

        // Some games keep the executable in a nested "Game" folder.
        let enumerator = fileManager.enumerator(
            at: installURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let candidate = enumerator?.nextObject() as? URL {
            if install.executableNames.contains(candidate.lastPathComponent.lowercased()) {
                return candidate
            }
        }

        return nil
    }

    private func localURL(forWinePath path: String) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard normalized.count > 2,
              normalized[normalized.index(normalized.startIndex, offsetBy: 1)] == ":" else {
            return nil
        }

        let drive = normalized.prefix(1).lowercased()
        var remainder = String(normalized.dropFirst(2))
        while remainder.hasPrefix("/") { remainder.removeFirst() }
        guard !remainder.isEmpty else { return nil }

        if drive == "z" {
            return URL(fileURLWithPath: "/" + remainder)
        }
        if drive == "c" {
            return url.appendingPathComponent("drive_c", isDirectory: true)
                .appendingPathComponent(remainder)
        }

        let device = url.appendingPathComponent("dosdevices", isDirectory: true)
            .appendingPathComponent("\(drive):")
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(
            atPath: device.path(percentEncoded: false)
        ) else {
            return nil
        }
        let root: URL
        if destination.hasPrefix("/") {
            root = URL(fileURLWithPath: destination)
        } else {
            root = device.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
        }
        return root.appendingPathComponent(remainder)
    }

    private func pinHoYoPlayGame(_ executableURL: URL, displayName: String) {
        if let existing = programs.first(where: {
            $0.url.path().caseInsensitiveCompare(executableURL.path()) == .orderedSame
        }) {
            existing.pinned = true
            return
        }

        let alreadyPinned = settings.pins.contains {
            $0.url?.path().caseInsensitiveCompare(executableURL.path()) == .orderedSame
        }
        if !alreadyPinned {
            settings.pins.append(PinnedProgram(name: displayName, url: executableURL))
        }

        let program = Program(url: executableURL, bottle: self)
        programs.append(program)
        programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func isUninstallerShortcut(name: String, programURL: URL) -> Bool {
        if Program.isUninstallerExecutable(programURL) {
            return true
        }

        let lowered = name.lowercased()
        let markers = [
            "uninstall", "unins", "卸载", "解除安裝", "アンインストール", "제거", "desinstalar"
        ]
        return markers.contains { lowered.contains($0) }
    }

    /// Picks the most representative shortcut name for a program.
    ///
    /// Prefer the name matching the target's folder or executable so a
    /// multi-game launcher is named after itself ("HoYoPlay") instead of an
    /// arbitrary game shortcut.
    private func preferredShortcutName(for url: URL, candidates: [String]) -> String {
        let expected = [
            url.deletingLastPathComponent().lastPathComponent.lowercased(),
            url.deletingPathExtension().lastPathComponent.lowercased()
        ].filter { !$0.isEmpty }

        if let match = candidates.first(where: { expected.contains($0.lowercased()) }) {
            return match
        }

        if let match = candidates.first(where: { candidate in
            let lowered = candidate.lowercased()
            return expected.contains(where: { lowered.contains($0) })
        }) {
            return match
        }

        return candidates.sorted { $0.lowercased() < $1.lowercased() }.first
            ?? url.deletingPathExtension().lastPathComponent
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
