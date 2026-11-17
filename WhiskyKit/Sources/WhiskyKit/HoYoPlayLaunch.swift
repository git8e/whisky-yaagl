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

    /// Posted when the last HoYoPlay launcher/helper process has exited.
    /// The main UI uses this to rescan the prefix registry after the user
    /// associates a game inside HoYoPlay.
    public static let launcherDidCloseNotification = Notification.Name(
        "Whisky.HoYoPlayLaunch.launcherDidClose"
    )

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

    /// Experimental: watch for a game started by HoYoPlay's own launcher.
    ///
    /// HoYoPlay starts the game directly, bypassing the bottle's patching and
    /// launch arguments. When that happens the native process is terminated
    /// and the same executable is started through `Program.runInWine()`, which
    /// applies this bottle's patch pipeline.
    public static func startGameLaunchInterceptor(bottle: Bottle) {
        Task {
            await GameLaunchInterceptor.shared.start(bottle: bottle)
        }
    }

    /// Mark a game executable as being started by Whisky itself so the
    /// HoYoPlay launch interceptor never mistakes it for a native launch.
    public static func markGameLaunchOwned(_ url: URL, owned: Bool) {
        GameLaunchOwnership.shared.mark(url, owned: owned)
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
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: HoYoPlayLaunch.launcherDidCloseNotification,
                        object: nil
                    )
                }
            }
        }

        private func finished() {
            running = false
        }
    }

    private actor GameLaunchInterceptor {
        static let shared = GameLaunchInterceptor()
        private var running = false

        func start(bottle: Bottle) {
            guard !running else { return }
            running = true

            Task.detached(priority: .utility) {
                await self.monitor(bottle: bottle)
            }
        }

        private func monitor(bottle: Bottle) async {
            // Ignore games that were already running before this launcher
            // session started. Only a new process can be a HoYoPlay launch.
            let initialPIDs = Set(HoYoPlayLaunch.gameProcesses(for: nil).map(\.pid))
            let startedAt = Date()
            var sawLauncher = false
            var missingLauncherSince: Date?

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if Task.isCancelled { break }

                if HoYoPlayLaunch.hasLauncherProcesses() {
                    sawLauncher = true
                    missingLauncherSince = nil
                } else if sawLauncher {
                    if missingLauncherSince == nil {
                        missingLauncherSince = Date()
                    }
                    if let missingLauncherSince,
                       Date().timeIntervalSince(missingLauncherSince) > 30 {
                        break
                    }
                } else if Date().timeIntervalSince(startedAt) > 120 {
                    // The launcher never appeared; avoid polling forever.
                    break
                }

                guard let target = HoYoPlayLaunch.hoYoPlayGameTarget(for: bottle) else {
                    continue
                }
                if GameLaunchOwnership.shared.isOwned(target.executableURL) {
                    continue
                }

                let candidates = HoYoPlayLaunch.gameProcesses(for: target.executableURL)
                    .filter { !initialPIDs.contains($0.pid) }
                guard !candidates.isEmpty else { continue }

                // Block HoYoPlay's native launch. The launcher already started
                // the game, so terminate it before it can reach a login screen.
                for process in candidates {
                    _ = HoYoPlayLaunch.terminate(pid: process.pid)
                }
                for _ in 0..<10 {
                    let remaining = HoYoPlayLaunch.gameProcesses(for: target.executableURL)
                        .filter { !initialPIDs.contains($0.pid) }
                    if remaining.isEmpty { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }

                // Mark ownership before starting our own process, then let
                // `runInWine()` hold the mark until the game exits.
                GameLaunchOwnership.shared.mark(target.executableURL, owned: true)
                await MainActor.run {
                    let program = HoYoPlayLaunch.associate(target, with: bottle)
                    program.runInWine()
                }
                GameLaunchOwnership.shared.mark(target.executableURL, owned: false)

                Logger.wineKit.info(
                    "Intercepted a native HoYoPlay game launch and relaunched it through Whisky"
                )
            }

            running = false
        }
    }

    private struct HoYoPlayGameTarget {
        let executableURL: URL
        let kind: BottleGamePreset
        let isChina: Bool

        var displayName: String {
            switch kind {
            case .hk4e:
                return "Genshin Impact"
            case .nap:
                return "Zenless Zone Zero"
            case .hkrpg:
                return "Honkai: Star Rail"
            }
        }
    }

    private static let gameExecutableNames = [
        "genshinimpact.exe",
        "yuanshen.exe",
        "zenlesszonezero.exe",
        "starrail.exe"
    ]

    private static let hoyoPlayBusinessNames = [
        "hk4e_global", "hk4e_cn",
        "nap_global", "nap_cn",
        "hkrpg_global", "hkrpg_cn"
    ]

    private static func hoYoPlayGameTarget(for bottle: Bottle) -> HoYoPlayGameTarget? {
        let settings = bottle.settings

        switch settings.gamePreset {
        case .hk4e:
            if let url = settings.hk4eGameExecutableURL,
               FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return HoYoPlayGameTarget(
                    executableURL: url,
                    kind: .hk4e,
                    isChina: settings.hk4eRegion.rawValue == "cn"
                )
            }
        case .nap:
            if let url = settings.napGameExecutableURL,
               FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return HoYoPlayGameTarget(
                    executableURL: url,
                    kind: .nap,
                    isChina: settings.napRegion.rawValue == "cn"
                )
            }
        case .hkrpg:
            if let url = settings.hkrpgGameExecutableURL,
               FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return HoYoPlayGameTarget(
                    executableURL: url,
                    kind: .hkrpg,
                    isChina: settings.hkrpgRegion.rawValue == "cn"
                )
            }
        }

        return registeredHoYoPlayGames(for: bottle).first {
            $0.kind.rawValue == settings.gamePreset.rawValue
        }
    }

    private static func gameProcesses(for target: URL?) -> [LauncherProcess] {
        let names = target.map { [$0.lastPathComponent.lowercased()] } ?? gameExecutableNames
        return launcherProcesses().filter { process in
            let command = process.command.lowercased()
            guard !command.contains("hoyoplay") else { return false }
            return names.contains { command.contains($0) }
        }
    }

    /// Read the game paths HoYoPlay writes to `user.reg`. This is also used by
    /// the main UI's association refresh; keep the Wine section-header parsing
    /// tolerant of the timestamp Wine appends after the closing bracket.
    private static func registeredHoYoPlayGames(for bottle: Bottle) -> [HoYoPlayGameTarget] {
        let registryURL = bottle.url.appending(path: "user.reg")
        guard let data = try? Data(contentsOf: registryURL),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }

        var games: [HoYoPlayGameTarget] = []
        var business: String?
        var installPath: String?

        func flush() {
            if let business,
               let installPath,
               !installPath.isEmpty,
               let kind = gameKind(forBusiness: business),
               let installURL = localURL(forWinePath: installPath, bottle: bottle),
               let executableURL = gameExecutable(
                   in: installURL,
                   names: executableNames(forBusiness: business)
               ) {
                games.append(HoYoPlayGameTarget(
                    executableURL: executableURL,
                    kind: kind,
                    isChina: business.hasSuffix("_cn")
                ))
            }
            business = nil
            installPath = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("["), let closing = line.firstIndex(of: "]") {
                flush()
                let key = line[line.index(after: line.startIndex)..<closing]
                let section = unescapeRegistry(String(key))
                if section.contains("\\Cognosphere\\HYP\\1_0\\"),
                   let last = section.split(separator: "\\").last.map(String.init),
                   hoyoPlayBusinessNames.contains(last) {
                    business = last
                }
                continue
            }

            guard business != nil else { continue }
            if line.hasPrefix("\"GameBiz\"") {
                if let value = registryValue(from: line),
                   hoyoPlayBusinessNames.contains(value) {
                    business = value
                }
            } else if line.hasPrefix("\"GameInstallPath\"") {
                installPath = registryValue(from: line)
            }
        }
        flush()

        return games
    }

    private static func gameKind(forBusiness business: String) -> BottleGamePreset? {
        if business.hasPrefix("hk4e") { return .hk4e }
        if business.hasPrefix("nap") { return .nap }
        if business.hasPrefix("hkrpg") { return .hkrpg }
        return nil
    }

    private static func executableNames(forBusiness business: String) -> [String] {
        switch gameKind(forBusiness: business) {
        case .hk4e:
            return ["genshinimpact.exe", "yuanshen.exe"]
        case .nap:
            return ["zenlesszonezero.exe"]
        case .hkrpg:
            return ["starrail.exe"]
        case nil:
            return []
        }
    }

    private static func gameExecutable(in directory: URL, names: [String]) -> URL? {
        let fileManager = FileManager.default
        for name in names {
            let direct = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: direct.path(percentEncoded: false)) {
                return direct
            }
        }

        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let candidate = enumerator?.nextObject() as? URL {
            if names.contains(candidate.lastPathComponent.lowercased()) {
                return candidate
            }
        }
        return nil
    }

    private static func localURL(forWinePath path: String, bottle: Bottle) -> URL? {
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
            return bottle.url.appendingPathComponent("drive_c", isDirectory: true)
                .appendingPathComponent(remainder)
        }

        let device = bottle.url.appendingPathComponent("dosdevices", isDirectory: true)
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

    private static func registryValue(from line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        var value = String(line[line.index(after: equals)...])
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return unescapeRegistry(value)
    }

    private static func unescapeRegistry(_ value: String) -> String {
        value.replacingOccurrences(of: "\\\\", with: "\\")
    }

    @MainActor
    private static func associate(_ target: HoYoPlayGameTarget, with bottle: Bottle) -> Program {
        switch target.kind {
        case .hk4e:
            if bottle.settings.hk4eGameExecutableURL == nil {
                bottle.settings.hk4eGameExecutableURL = target.executableURL
            }
            bottle.settings.hk4eRegion = target.isChina ? .cn : .os
        case .nap:
            if bottle.settings.napGameExecutableURL == nil {
                bottle.settings.napGameExecutableURL = target.executableURL
            }
            bottle.settings.napRegion = target.isChina ? .cn : .os
        case .hkrpg:
            if bottle.settings.hkrpgGameExecutableURL == nil {
                bottle.settings.hkrpgGameExecutableURL = target.executableURL
            }
            bottle.settings.hkrpgRegion = target.isChina ? .cn : .os
        }

        let path = target.executableURL.path(percentEncoded: false)
        let program: Program
        if let existing = bottle.programs.first(where: {
            $0.url.path().caseInsensitiveCompare(path) == .orderedSame
        }) {
            program = existing
        } else {
            program = Program(url: target.executableURL, bottle: bottle)
            bottle.programs.append(program)
        }

        if !bottle.settings.pins.contains(where: {
            $0.url?.path().caseInsensitiveCompare(path) == .orderedSame
        }) {
            bottle.settings.pins.append(PinnedProgram(
                name: target.displayName,
                url: target.executableURL
            ))
        }

        return program
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

/// Tracks game processes started by Whisky itself so the HoYoPlay interceptor
/// does not terminate its own patched launch.
private final class GameLaunchOwnership: @unchecked Sendable {
    static let shared = GameLaunchOwnership()

    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    private func key(for url: URL) -> String {
        url.path(percentEncoded: false).lowercased()
    }

    func mark(_ url: URL, owned: Bool) {
        let key = key(for: url)
        lock.lock()
        defer { lock.unlock() }

        if owned {
            counts[key, default: 0] += 1
        } else if let count = counts[key] {
            if count <= 1 {
                counts[key] = nil
            } else {
                counts[key] = count - 1
            }
        }
    }

    func isOwned(_ url: URL) -> Bool {
        let key = key(for: url)
        lock.lock()
        defer { lock.unlock() }
        return (counts[key] ?? 0) > 0
    }
}

