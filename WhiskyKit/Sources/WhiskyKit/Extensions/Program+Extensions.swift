//
//  Program+Extensions.swift
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
import os.log

extension Program {
    private func validateTargetFileExists() -> String? {
        let targetPath = self.url.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: targetPath) else { return nil }
        return String(localized: "error.fileNotFound") + "\n\n" + targetPath
    }

    public func run() {
        if NSEvent.modifierFlags.contains(.shift) {
            self.runInTerminal()
        } else {
            self.runInWine()
        }
    }

    func runInWine() {
        if let missingMessage = validateTargetFileExists() {
            Task { @MainActor in
                self.isLaunching = false
                self.lastExitCode = nil
                self.showRunError(message: missingMessage)
            }
            return
        }

        let arguments = settings.arguments.split { $0.isWhitespace }.map(String.init)
        let environment = generateEnvironment()
        let hk4eExe = bottle.settings.hk4eGameExecutableURL
        let napExe = bottle.settings.napGameExecutableURL
        let hkrpgExe = bottle.settings.hkrpgGameExecutableURL
        let usesGamePatch = hk4eExe == url || napExe == url || hkrpgExe == url
        let windowSnapshot = usesGamePatch ? WineWindowSnapshot.capture() : nil

        // The HoYoPlay interceptor must ignore a game that Whisky itself is
        // starting; it is already using the patched launch path.
        HoYoPlayLaunch.markGameLaunchOwned(self.url, owned: true)

        Task.detached(priority: .userInitiated) {
            defer { HoYoPlayLaunch.markGameLaunchOwned(self.url, owned: false) }
            await MainActor.run {
                self.isLaunching = true
                self.hasVisibleWindow = false
                self.lastExitCode = nil
            }

            // The game patch waits for the real game process/host to exit, but
            // the window can appear much earlier. Stop the spinner when the
            // window is actually visible while keeping `isLaunching` set so a
            // second click cannot start another game instance.
            let windowWatcher: Task<Void, Never>?
            if let windowSnapshot {
                windowWatcher = Task {
                    _ = await WineWindowSnapshot.waitForNewWindow(since: windowSnapshot, timeout: 25)
                    await MainActor.run {
                        if self.isLaunching {
                            self.hasVisibleWindow = true
                        }
                    }
                }
            } else {
                windowWatcher = nil
            }
            defer { windowWatcher?.cancel() }

            do {
                try await Wine.withLogSession(for: self.bottle) {
                    if hk4eExe == self.url {
                        try await HK4ePatch.applyAndRun(program: self, args: arguments, environment: environment)
                    } else if napExe == self.url {
                        try await NAPPatch.applyAndRun(program: self, args: arguments, environment: environment)
                    } else if hkrpgExe == self.url {
                        try await HKRPGPatch.applyAndRun(program: self, args: arguments, environment: environment)
                    } else {
                        try await Wine.runProgram(
                            at: self.url, args: arguments, bottle: self.bottle, environment: environment
                        )
                    }
                }
                await MainActor.run {
                    self.isLaunching = false
                    self.lastExitCode = 0
                }
            } catch {
                let exitCode = (error as? HK4ePatchError).flatMap { err in
                    if case .gameExited(let code) = err { return code }
                    return nil
                } ?? (error as? NAPPatchError).flatMap { err in
                    if case .gameExited(let code) = err { return code }
                    return nil
                } ?? (error as? HKRPGPatchError).flatMap { err in
                    if case .gameExited(let code) = err { return code }
                    return nil
                }

                await MainActor.run {
                    self.isLaunching = false
                    self.hasVisibleWindow = false
                    self.lastExitCode = exitCode
                    self.showRunError(message: error.localizedDescription, exitCode: exitCode)
                }
            }
        }
    }

    public func generateTerminalCommand() -> String {
        return Wine.generateRunCommand(
            at: self.url, bottle: bottle, args: settings.arguments, environment: generateEnvironment()
        )
    }

    public func runInTerminal() {
        if let missingMessage = validateTargetFileExists() {
            Task { @MainActor in
                self.showRunError(message: missingMessage)
            }
            return
        }

        let wineCmd = generateTerminalCommand().replacingOccurrences(of: "\\", with: "\\\\")

        let script = """
        tell application "Terminal"
            activate
            do script "\(wineCmd)"
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

    @MainActor private func showRunError(message: String, exitCode: Int? = nil) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        var informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message

        if exitCode == 5 {
            informativeText += "\n\n" + String(localized: "alert.errorCode5Hint")
        }

        alert.informativeText = informativeText

        let latestLogURL = Wine.latestLogFileURL()

        alert.alertStyle = .critical

        if latestLogURL != nil {
            alert.addButton(withTitle: String(localized: "button.openLatestLog"))
        }
        alert.addButton(withTitle: String(localized: "button.ok"))
        let response = alert.runModal()

        if response == .alertFirstButtonReturn, let latestLogURL {
            NSWorkspace.shared.open(latestLogURL)
        }
    }
}
