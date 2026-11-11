//
//  HoYoPlayLaunch.swift
//  WhiskyKit
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
import os.log

/// Launch tweaks that HoYoPlay needs when DXMT is injected into the runtime.
public enum HoYoPlayLaunch {
    /// HoYoPlay's launcher (HYP) is CEF based. Its GPU process hands swap
    /// chains over to the browser process, which DXMT does not support yet:
    /// `CreateSwapChain: cross-process swapchain not supported yet`.
    /// The result is a missing or blank launcher window, so keep CEF's GPU
    /// work inside the browser process.
    public static let launcherArguments = ["--in-process-gpu"]

    /// The HoYoPlay installer is a Qt Quick application that initializes
    /// ANGLE. With DXMT's d3d11/dxgi in place Qt's graphics initialization can
    /// spin at 100% CPU and stop responding to input. Software rendering is
    /// more than enough for an installer UI.
    public static let installerEnvironment = [
        "QT_OPENGL": "software",
        "QT_ANGLE_PLATFORM": "warp",
        "QT_QUICK_BACKEND": "software"
    ]

    /// Helper that removes `WS_CAPTION` from HoYoPlay's main window.
    static var titleBarHelperURL: URL? {
        Bundle.module.url(forResource: "unframe-hyp", withExtension: "exe")
    }

    /// Hides the native macOS title bar above HoYoPlay's own header.
    ///
    /// HoYoPlay keeps `WS_CAPTION` on its top-level window, which makes Wine's
    /// Mac driver draw a real `NSWindow` title bar. Wine 11 removed the old
    /// per-application `Decorated` setting, so the caption is removed from
    /// inside Windows by a small helper that runs in the same prefix. The
    /// helper waits for the window to appear, so call this before launching.
    public static func hideNativeTitleBarIfNeeded(for url: URL, bottle: Bottle) {
        guard isLauncher(at: url), let helper = titleBarHelperURL else { return }

        Task.detached(priority: .utility) {
            do {
                let stream = try Wine.runWineProcess(
                    name: "unframe-hyp",
                    args: [helper.path(percentEncoded: false)],
                    bottle: bottle
                )
                for await _ in stream { }
            } catch {
                Logger.wineKit.warning(
                    "Could not start the HoYoPlay title bar helper: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Whether `url` points at the HoYoPlay launcher or its HYP executable.
    public static func isLauncher(at url: URL) -> Bool {
        guard url.path(percentEncoded: false)
            .range(of: "/HoYoPlay/", options: .caseInsensitive) != nil else {
            return false
        }

        let name = url.lastPathComponent.lowercased()
        return name == "launcher.exe" || name == "hyp.exe"
    }

    /// Extra command line arguments for `url`, skipping ones that are already present.
    public static func additionalArguments(for url: URL, existing: [String] = []) -> [String] {
        guard isLauncher(at: url) else { return [] }
        return launcherArguments.filter { !existing.contains($0) }
    }

    /// The installer automatically starts `HYP.exe --jump=installer` when it
    /// finishes. Under DXMT that instance never creates a window but stays
    /// alive and keeps HoYoPlay's singleton, which makes later launches exit
    /// immediately. Terminate those leftovers.
    ///
    /// - Returns: `true` when a leftover launcher process was terminated.
    @discardableResult
    public static func terminateInstallerLaunchedProcesses() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return false }

        var terminated = false
        for line in output.split(separator: "\n") where line.contains("HYP.exe --jump=installer") {
            let pidText = line.prefix(while: { $0 == " " || $0.isNumber })
            guard let pid = pid_t(pidText.trimmingCharacters(in: .whitespaces)) else { continue }
            if kill(pid, SIGTERM) == 0 {
                terminated = true
            }
        }

        return terminated
    }
}
