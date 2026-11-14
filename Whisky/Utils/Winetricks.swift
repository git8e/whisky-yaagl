//
//  Winetricks.swift
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

import CryptoKit
import Foundation
import AppKit
import WhiskyKit

enum WinetricksCategories: String {
    case apps
    case benchmarks
    case dlls
    case fonts
    case games
    case settings
}

struct WinetricksVerb: Identifiable {
    var id = UUID()

    var name: String
    var description: String
}

struct WinetricksCategory {
    var category: WinetricksCategories
    var verbs: [WinetricksVerb]
}

class Winetricks {
    static let winetricksURL: URL = WhiskyWineInstaller.libraryFolder
        .appending(path: "winetricks")

    /// Pinned winetricks release used when the support files are not present.
    /// Older WhiskyWine installs placed these in `Libraries`; the per-bottle
    /// runtime layout does not, which leaves the verb list empty.
    private static let supportDownloadURLString =
        "https://raw.githubusercontent.com/Winetricks/winetricks/20260125/src/winetricks"
    private static let supportSHA256 =
        "431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b"

    private static func ensureSupportFiles() async {
        let fileManager = FileManager.default
        let library = WhiskyWineInstaller.libraryFolder
        try? fileManager.createDirectory(at: library, withIntermediateDirectories: true)

        let scriptPath = winetricksURL.path(percentEncoded: false)
        if !fileManager.fileExists(atPath: scriptPath) {
            guard let supportDownloadURL = URL(string: supportDownloadURLString) else { return }
            do {
                var request = URLRequest(url: supportDownloadURL)
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return
                }
                let digest = SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
                guard digest.caseInsensitiveCompare(supportSHA256) == .orderedSame else {
                    return
                }
                try data.write(to: winetricksURL, options: .atomic)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: scriptPath
                )
            } catch {
                return
            }
        } else if !fileManager.isExecutableFile(atPath: scriptPath) {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptPath
            )
        }

        let verbsURL = library.appending(path: "verbs.txt")
        let existing = (try? Data(contentsOf: verbsURL)) ?? Data()
        guard existing.isEmpty else { return }
        guard let output = generateVerbs(), !output.isEmpty else { return }
        try? output.write(to: verbsURL, atomically: true, encoding: .utf8)
    }

    private static func generateVerbs() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [winetricksURL.path(percentEncoded: false), "list-all"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func runCommand(command: String, bottle: Bottle) async {
        await ensureSupportFiles()
        guard let resourcesURL = Bundle.main.url(forResource: "cabextract", withExtension: nil)?
            .deletingLastPathComponent() else { return }
        let binFolder = WineRuntimeManager.binFolder(bottle: bottle)
        let wineBinaryName = WineRuntimeManager.wineBinary(bottle: bottle).lastPathComponent
        // swiftlint:disable:next line_length
        let winetricksCmd = #"PATH=\"\#(binFolder.path):\#(resourcesURL.path(percentEncoded: false)):$PATH\" WINE=\#(wineBinaryName) WINEPREFIX=\"\#(bottle.url.path)\" \"\#(winetricksURL.path(percentEncoded: false))\" \#(command)"#

        let script = """
        tell application "Terminal"
            activate
            do script "\(winetricksCmd)"
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                print(error)
                if let description = error["NSAppleScriptErrorMessage"] as? String {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = String(localized: "alert.message")
                        alert.informativeText = String(localized: "alert.info")
                            + " \(command): "
                            + description
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: String(localized: "button.ok"))
                        alert.runModal()
                    }
                }
            }
        }
    }

    static func parseVerbs() async -> [WinetricksCategory] {
        await ensureSupportFiles()

        // Grab the verbs file
        let verbsURL = WhiskyWineInstaller.libraryFolder.appending(path: "verbs.txt")
        let verbs: String = await { () async -> String in
            do {
                let (data, _) = try await URLSession.shared.data(from: verbsURL)
                return String(data: data, encoding: .utf8) ?? String()
            } catch {
                return String()
            }
        }()

        // Read the file line by line
        let lines = verbs.components(separatedBy: "\n")
        var categories: [WinetricksCategory] = []
        var currentCategory: WinetricksCategory?

        for line in lines {
            // Categories are label as "===== <name> ====="
            if line.starts(with: "=====") {
                // If we have a current category, add it to the list
                if let currentCategory = currentCategory {
                    categories.append(currentCategory)
                }

                // Create a new category
                // Capitalize the first letter of the category name
                let categoryName = line.replacingOccurrences(of: "=====", with: "").trimmingCharacters(in: .whitespaces)
                if let cateogry = WinetricksCategories(rawValue: categoryName) {
                    currentCategory = WinetricksCategory(category: cateogry,
                                                         verbs: [])
                } else {
                    currentCategory = nil
                }
            } else {
                guard currentCategory != nil else {
                    continue
                }

                // If we have a current category, add the verb to it
                // Verbs eg. "3m_library               3M Cloud Library (3M Company, 2015) [downloadable]"
                let verbName = line.components(separatedBy: " ")[0]
                let verbDescription = line.replacingOccurrences(of: "\(verbName) ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentCategory?.verbs.append(WinetricksVerb(name: verbName, description: verbDescription))
            }
        }

        // Add the last category
        if let currentCategory = currentCategory {
            categories.append(currentCategory)
        }

        return categories
    }
}
