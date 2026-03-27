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

        Task.detached(priority: .userInitiated) {
            await MainActor.run {
                self.isLaunching = true
                self.lastExitCode = nil
            }
            do {
                try await Wine.withLogSession(for: self.bottle) {
                    let hk4eExe = self.bottle.settings.hk4eGameExecutableURL
                    let napExe = self.bottle.settings.napGameExecutableURL

                    if hk4eExe == self.url {
                        try await HK4ePatch.applyAndRun(program: self, args: arguments, environment: environment)
                    } else if napExe == self.url {
                        try await NAPPatch.applyAndRun(program: self, args: arguments, environment: environment)
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
                await MainActor.run {
                    self.isLaunching = false
                    self.lastExitCode = (error as? HK4ePatchError).flatMap { err in
                        if case .gameExited(let code) = err { return code }
                        return nil
                    } ?? (error as? NAPPatchError).flatMap { err in
                        if case .gameExited(let code) = err { return code }
                        return nil
                    }
                }
                await MainActor.run {
                    self.showRunError(message: error.localizedDescription)
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

    @MainActor private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message

        let latestLogURL = Wine.latestLogFileURL()
        let logURL = latestLogURL ?? Wine.logsFolder
        let logLabel = (latestLogURL != nil) ? "Log:" : "Logs:"

        let fullPath = logURL.path(percentEncoded: false)
        let displayPath = (fullPath as NSString).abbreviatingWithTildeInPath

        // NSAlert informative text is plain; use an accessory view so the path is selectable and wraps.
        let labelField = NSTextField(labelWithString: logLabel)
        labelField.alignment = .left
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = displayPath
        textView.toolTip = fullPath
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byCharWrapping

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalToConstant: 480).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let accessory = NSStackView(views: [labelField, scrollView])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 4
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        alert.accessoryView = accessory

        alert.alertStyle = .critical
        let openTitle = String(localized: latestLogURL != nil ? "button.openLatestLog" : "button.openLogs")
        alert.addButton(withTitle: openTitle)
        alert.addButton(withTitle: String(localized: "button.ok"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(logURL)
        }
    }
}
