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

import AppKit
import CoreGraphics
import Darwin
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

    /// Activate the first new Wine window after `snapshot`. Installers started
    /// with `wine start` can open behind Whisky, which makes their buttons look
    /// unresponsive until the window is clicked once.
    @discardableResult
    public static func activateNewWindow(
        since snapshot: WineWindowSnapshot.Snapshot,
        timeout: TimeInterval = 25
    ) async -> Bool {
        guard let pid = await WineWindowSnapshot.waitForNewWindowOwnerPID(
            since: snapshot,
            timeout: timeout
        ) else {
            return false
        }

        await MainActor.run {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        }
        return true
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
    /// immediately. A normal launcher can also leave a hidden HYP process
    /// behind after its window is closed.
    ///
    /// - Returns: `true` when a leftover launcher process was terminated.
    @discardableResult
    public static func terminateInstallerLaunchedProcesses() -> Bool {
        terminateStaleLauncherProcesses()
    }

    /// Terminate HYP/launcher processes that cannot show a window.
    ///
    /// Starting HYP under Wine can take more than ten seconds before its CEF
    /// window appears, so only processes older than the startup grace period
    /// are considered stale. Healthy launchers (ones with a visible window)
    /// and games are never touched.
    @discardableResult
    public static func terminateStaleLauncherProcesses() -> Bool {
        let processes = launcherProcesses()
        guard !processes.isEmpty else { return false }

        let hyps = processes.filter {
            $0.command.contains("HoYoPlay") && $0.command.contains("HYP.exe") && !$0.command.contains("HYPHelper")
        }
        let launchers = processes.filter {
            $0.command.contains("HoYoPlay")
                && ($0.command.contains("/launcher.exe") || $0.command.contains("\\launcher.exe"))
        }
        let helperStartupGrace: TimeInterval = 10
        let startupGrace: TimeInterval = 20

        let healthyHYP = hyps.contains { !$0.command.contains("--jump=installer") && hasVisibleWindow(pid: $0.pid) }
        let activeStartup = hyps.contains {
            !$0.command.contains("--jump=installer") && $0.elapsed < startupGrace && !hasVisibleWindow(pid: $0.pid)
        }

        var terminated = false

        for process in hyps + launchers {
            let isInstaller = process.command.contains("--jump=installer")
            let isStale = isInstaller
                || (process.elapsed >= startupGrace && !hasVisibleWindow(pid: process.pid))
            guard isStale else { continue }

            // If another HYP is visibly healthy, leave its helper processes
            // alone. Only the broken instance is removed.
            if terminate(pid: process.pid) {
                terminated = true
            }
        }

        // If there is no healthy HYP and no launcher still starting, clean up
        // orphaned CEF helpers as well. They are the processes that keep the
        // bottle alive and make the next launch look like it did nothing.
        if !healthyHYP && !activeStartup {
            for process in processes
            where process.command.contains("HoYoPlay") && process.command.contains("HYPHelper")
                && process.elapsed >= helperStartupGrace {
                if terminate(pid: process.pid) {
                    terminated = true
                }
            }
        }

        if terminated {
            Logger.wineKit.info("Terminated stale HoYoPlay processes")
        }
        return terminated
    }

    /// Start a lightweight watcher that removes HYP/CEF after the launcher
    /// window is closed but its process stays alive. Only one watcher runs at a
    /// time and it exits automatically when no HoYoPlay process remains.
    public static func startStaleProcessMonitor() {
        Task {
            await LauncherProcessMonitor.shared.start()
        }
    }

    /// Whether any HoYoPlay launcher/helper process is still running.
    public static func hasLauncherProcesses() -> Bool {
        launcherProcesses().contains {
            $0.command.contains("HoYoPlay")
                && ($0.command.contains("HYP.exe") || $0.command.contains("HYPHelper")
                    || $0.command.contains("/launcher.exe") || $0.command.contains("\\launcher.exe"))
        }
    }

    private actor LauncherProcessMonitor {
        static let shared = LauncherProcessMonitor()
        private var running = false

        func start() {
            guard !running else { return }
            running = true

            Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if Task.isCancelled { break }
                    _ = HoYoPlayLaunch.terminateStaleLauncherProcesses()
                    if !HoYoPlayLaunch.hasLauncherProcesses() { break }
                }
                await self.finished()
            }
        }

        private func finished() {
            running = false
        }
    }

    private struct LauncherProcess {
        let pid: pid_t
        let elapsed: TimeInterval
        let command: String
    }

    private static func launcherProcesses() -> [LauncherProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,etime=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var result: [LauncherProcess] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = pid_t(parts[0]),
                  let elapsed = parseElapsed(String(parts[1])) else {
                continue
            }
            result.append(LauncherProcess(pid: pid, elapsed: elapsed, command: String(parts[2])))
        }
        return result
    }

    private static func parseElapsed(_ value: String) -> TimeInterval? {
        var days = 0
        var time = value
        if let dash = value.firstIndex(of: "-") {
            days = Int(value[..<dash]) ?? 0
            time = String(value[value.index(after: dash)...])
        }

        let fields = time.split(separator: ":").compactMap { Double($0) }
        var seconds: Double
        switch fields.count {
        case 3:
            seconds = fields[0] * 3600 + fields[1] * 60 + fields[2]
        case 2:
            seconds = fields[0] * 60 + fields[1]
        case 1:
            seconds = fields[0]
        default:
            return nil
        }
        seconds += Double(days) * 86_400
        return seconds
    }

    private static func hasVisibleWindow(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in windows {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid else {
                continue
            }
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            guard layer == 0 else { continue }

            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            if width >= 80 && height >= 60 {
                return true
            }
        }
        return false
    }

    private static func terminate(pid: pid_t) -> Bool {
        guard kill(pid, SIGTERM) == 0 else { return false }
        usleep(200_000)
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
        return true
    }
}
