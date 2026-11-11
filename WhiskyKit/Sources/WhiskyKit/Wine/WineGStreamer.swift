//
//  WineGStreamer.swift
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
import CryptoKit
import os.log

/// Installs a shared GStreamer framework and patches isolated Wine runtimes to
/// use it.
///
/// Wine's `winegstreamer.so` is built with a hard-coded
/// `/Library/Frameworks/GStreamer.framework/Libraries` rpath. On machines
/// without a system-wide GStreamer install that library cannot be loaded, so
/// Wine's media foundation (and anything else using `winegstreamer`) is
/// unavailable. This type mirrors the per-runtime DXMT injection: the base
/// runtime is left untouched, while each bottle's isolated `WineRuntime` copy
/// receives a symlink to the shared framework plus relative rpaths on
/// `winegstreamer.so`.
public actor WineGStreamer {
    public static let shared = WineGStreamer()

    /// Version of the pinned GStreamer runtime package. The `-rN` suffix is our
    /// component-set revision, not a different upstream GStreamer release.
    public static let frameworkVersion = "1.28.8-r2"

    private static let packageName = "gstreamer-1.0-1.28.8-universal.pkg"
    private static let packageURL = URL(
        string: "https://gstreamer.freedesktop.org/data/pkg/osx/1.28.8/\(packageName)"
    )!
    private static let packageSHA256 = "d371ab04a7632713626836c2fc234e863cc98484c74c473eba99b0fbd9b3a3fe"

    /// Component packages required for decoding/playback. The full installer
    /// also contains devtools, Python, GTK, and large networking plugin sets,
    /// which are unnecessary for `winegstreamer` and would add hundreds of
    /// megabytes to every install.
    private static let componentPackages = [
        "base-system-1.0",
        "base-crypto",
        "gstreamer-1.0-core",
        "gstreamer-1.0-playback",
        "gstreamer-1.0-codecs",
        "gstreamer-1.0-codecs-restricted",
        "gstreamer-1.0-libav",
        "gstreamer-1.0-system",
        "gstreamer-1.0-effects"
    ]

    /// Relative rpaths added to `winegstreamer.so`. The library lives in
    /// `<runtime>/lib/wine/x86_64-unix`, so `../../` resolves to `<runtime>/lib`.
    private static let requiredRPaths = [
        "@loader_path/../../GStreamer.framework/Versions/1.0/lib",
        "@loader_path/../../GStreamer.framework/Libraries"
    ]

    private static var fm: FileManager { FileManager.default }
    private static let logger = Logger(subsystem: "com.whisky.WhiskyKit", category: "WineGStreamer")

    /// `~/Library/Application Support/whisky-yaagl/Libraries/GStreamer`
    public static var libraryRoot: URL {
        WhiskyWineInstaller.libraryFolder.appending(path: "GStreamer", directoryHint: .isDirectory)
    }

    /// The shared, complete framework used by every patched runtime.
    public static var frameworkURL: URL {
        libraryRoot.appending(path: "GStreamer.framework", directoryHint: .isDirectory)
    }

    private static var versionFileURL: URL {
        libraryRoot.appending(path: "installed-version.txt", directoryHint: .notDirectory)
    }

    public static func installedFrameworkVersion() -> String? {
        guard fm.fileExists(atPath: versionFileURL.path(percentEncoded: false)) else {
            return nil
        }
        return try? String(contentsOf: versionFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isFrameworkInstalled() -> Bool {
        isFrameworkValid(at: frameworkURL)
    }

    /// Download (once) and install the shared GStreamer framework.
    ///
    /// The package is verified against a pinned SHA-256 before extraction. The
    /// framework is assembled from a small, curated component set so it only
    /// contains what media playback needs.
    public func ensureInstalled(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        Self.cleanupStaleInstallArtifacts()

        if Self.isFrameworkInstalled() {
            let installed = Self.installedFrameworkVersion()
            if installed == nil || installed == Self.frameworkVersion {
                if installed == nil {
                    try? Self.fm.createDirectory(at: Self.libraryRoot, withIntermediateDirectories: true)
                    try? Data(Self.frameworkVersion.utf8).write(to: Self.versionFileURL, options: .atomic)
                }
                progress?(1)
                return
            }
        }

        try Self.fm.createDirectory(at: Self.libraryRoot, withIntermediateDirectories: true)

        let pkgURL = Self.libraryRoot.appending(path: Self.packageName, directoryHint: .notDirectory)
        if Self.fm.fileExists(atPath: pkgURL.path(percentEncoded: false)) {
            progress?(0.8)
        } else {
            try await RemoteDownloader.downloadOnce(url: Self.packageURL, destination: pkgURL) { fraction in
                progress?(min(max(fraction * 0.8, 0), 0.8))
            }
        }

        let digest = try await Task.detached(priority: .utility) {
            try Self.sha256(of: pkgURL)
        }.value
        guard digest.lowercased() == Self.packageSHA256 else {
            try? Self.fm.removeItem(at: pkgURL)
            throw WineGStreamerError.integrityCheckFailed
        }

        let tempDir = Self.libraryRoot.appending(path: "Temp-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? Self.fm.removeItem(at: tempDir) }

        // `pkgutil --expand-full` creates the destination itself and refuses to
        // expand into an existing directory.
        try Self.run(
            "/usr/sbin/pkgutil",
            ["--expand-full", pkgURL.path(percentEncoded: false), tempDir.path(percentEncoded: false)]
        )
        progress?(0.9)

        let payloads = try Self.payloadDirectories(in: tempDir)
        guard let skeleton = Self.payload(in: payloads, for: "osx-framework") else {
            throw WineGStreamerError.invalidPackage("missing osx-framework payload")
        }

        let staging = Self.libraryRoot.appending(
            path: "GStreamer.framework.new-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? Self.fm.removeItem(at: staging)

        do {
            try Self.ditto(skeleton, staging)
            let version10 = staging.appending(path: "Versions/1.0", directoryHint: .isDirectory)
            for component in Self.componentPackages {
                guard let payload = Self.payload(in: payloads, for: component) else {
                    throw WineGStreamerError.invalidPackage("missing \(component) payload")
                }
                try Self.ditto(payload, version10)
            }

            guard Self.isFrameworkValid(at: staging) else {
                throw WineGStreamerError.invalidFramework
            }

            let destination = Self.frameworkURL
            if Self.fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                try Self.fm.removeItem(at: destination)
            }
            try Self.fm.moveItem(at: staging, to: destination)
            Self.removeQuarantineRecursively(at: destination)
        } catch {
            try? Self.fm.removeItem(at: staging)
            throw error
        }

        try Data(Self.frameworkVersion.utf8).write(to: Self.versionFileURL, options: .atomic)
        try? Self.fm.removeItem(at: pkgURL)
        Self.logger.info("Installed GStreamer \(Self.frameworkVersion, privacy: .public)")
        progress?(1)
    }

    /// Ensure the framework exists, then patch the given isolated runtime.
    ///
    /// The patch is idempotent: a marker next to `winegstreamer.so` makes
    /// subsequent calls cheap, and the framework link is re-created if it was
    /// removed.
    public func ensureInstalledAndPatch(
        runtimeRoot: URL,
        createFrameworkLink: Bool = true,
        status: (@Sendable (String) -> Void)? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let winegstreamer = runtimeRoot.appending(
            path: "lib/wine/x86_64-unix/winegstreamer.so",
            directoryHint: .notDirectory
        )
        guard Self.fm.fileExists(atPath: winegstreamer.path(percentEncoded: false)) else {
            return
        }

        if Self.isFrameworkInstalled(), Self.installedFrameworkVersion() == Self.frameworkVersion {
            progress?(1)
        } else {
            status?("Installing GStreamer media support")
            try await ensureInstalled(progress: progress)
        }

        status?("Patching Wine media support")
        try applyToRuntime(runtimeRoot: runtimeRoot, createFrameworkLink: createFrameworkLink)
    }

    /// Patch a runtime copy in place.
    ///
    /// This does not touch the base runtime. The isolated runtime is disposable
    /// and is recreated whenever the bottle's base runtime changes.
    public func applyToRuntime(runtimeRoot: URL, createFrameworkLink: Bool = true) throws {
        let winegstreamer = runtimeRoot.appending(
            path: "lib/wine/x86_64-unix/winegstreamer.so",
            directoryHint: .notDirectory
        )
        guard Self.fm.fileExists(atPath: winegstreamer.path(percentEncoded: false)) else {
            return
        }

        if createFrameworkLink {
            let link = runtimeRoot.appending(path: "lib/GStreamer.framework", directoryHint: .notDirectory)
            do {
                try Self.installFrameworkLink(at: link)
            } catch {
                // A bottle on a filesystem without symlink support (for
                // example exFAT) can still use the shared framework through the
                // DYLD fallback environment. Keep patching the dylib.
                Self.logger.error("Failed to link GStreamer framework: \(error.localizedDescription, privacy: .public)")
            }
        }

        let marker = winegstreamer.deletingLastPathComponent()
            .appending(path: ".gstreamer-\(Self.frameworkVersion)", directoryHint: .notDirectory)
        if Self.fm.fileExists(atPath: marker.path(percentEncoded: false)) {
            return
        }

        let existing = Self.existingRPaths(of: winegstreamer)
        let missing = Self.requiredRPaths.filter { !existing.contains($0) }
        if !missing.isEmpty {
            let backup = winegstreamer.appendingPathExtension("orig")
            if !Self.fm.fileExists(atPath: backup.path(percentEncoded: false)) {
                try FileCopy.copyItem(at: winegstreamer, to: backup)
            }

            do {
                for rpath in missing {
                    try Self.run(
                        "/usr/bin/install_name_tool",
                        ["-add_rpath", rpath, winegstreamer.path(percentEncoded: false)]
                    )
                }
                try Self.run(
                    "/usr/bin/codesign",
                    ["--force", "--sign", "-", winegstreamer.path(percentEncoded: false)]
                )
            } catch {
                // A partially modified or re-signed library must not be left
                // behind: restore the original so unrelated media still works.
                if Self.fm.fileExists(atPath: backup.path(percentEncoded: false)) {
                    try? Self.fm.removeItem(at: winegstreamer)
                    try? Self.fm.moveItem(at: backup, to: winegstreamer)
                }
                throw error
            }
        }

        try Data(Self.frameworkVersion.utf8).write(to: marker, options: .atomic)
        Self.logger.info(
            "Patched \(runtimeRoot.lastPathComponent, privacy: .public) for GStreamer \(Self.frameworkVersion, privacy: .public)"
        )
    }

    /// Undo the runtime patch. Used for troubleshooting and when a runtime is
    /// moved back to a stock configuration.
    public func revertRuntime(runtimeRoot: URL) throws {
        let winegstreamer = runtimeRoot.appending(
            path: "lib/wine/x86_64-unix/winegstreamer.so",
            directoryHint: .notDirectory
        )
        let backup = winegstreamer.appendingPathExtension("orig")
        if Self.fm.fileExists(atPath: backup.path(percentEncoded: false)) {
            if Self.fm.fileExists(atPath: winegstreamer.path(percentEncoded: false)) {
                try? Self.fm.removeItem(at: winegstreamer)
            }
            try Self.fm.moveItem(at: backup, to: winegstreamer)
        }

        let link = runtimeRoot.appending(path: "lib/GStreamer.framework", directoryHint: .notDirectory)
        if (try? Self.fm.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))) != nil {
            try? Self.fm.removeItem(at: link)
        }

        let marker = winegstreamer.deletingLastPathComponent()
            .appending(path: ".gstreamer-\(Self.frameworkVersion)", directoryHint: .notDirectory)
        try? Self.fm.removeItem(at: marker)
        Self.logger.info("Reverted GStreamer runtime patch: \(runtimeRoot.lastPathComponent, privacy: .public)")
    }

    /// Environment variables that make the bundled framework and plugins
    /// discoverable even if the relative rpath patch is unavailable (for
    /// example when a base runtime is used directly).
    public static func environment(forRuntimeRoot root: URL) -> [String: String] {
        let runtimeFramework = root.appending(path: "lib/GStreamer.framework", directoryHint: .isDirectory)
        // Prefer the shared framework (the same one the runtime symlink points
        // at). This keeps the environment stable even if a runtime has a stale
        // or dangling link.
        let framework = fm.fileExists(atPath: frameworkURL.path(percentEncoded: false))
            ? frameworkURL
            : runtimeFramework
        let version10 = framework.appending(path: "Versions/1.0", directoryHint: .isDirectory)
        let lib = version10.appending(path: "lib", directoryHint: .isDirectory)
        let plugins = lib.appending(path: "gstreamer-1.0", directoryHint: .isDirectory)
        let scanner = version10.appending(
            path: "libexec/gstreamer-1.0/gst-plugin-scanner",
            directoryHint: .notDirectory
        )

        guard fm.fileExists(atPath: lib.path(percentEncoded: false)) else {
            return [:]
        }

        var result: [String: String] = [
            "GST_PLUGIN_SYSTEM_PATH": plugins.path(percentEncoded: false),
            "GST_PLUGIN_SYSTEM_PATH_1_0": plugins.path(percentEncoded: false),
            "DYLD_FALLBACK_LIBRARY_PATH": lib.path(percentEncoded: false),
            // Some Media Foundation sources pass raw AAC frames, while others
            // use ADTS. `atdec` (AudioToolbox) rejects the ADTS caps and then
            // never produces output, so prefer libav's AAC decoder. Keep
            // `aacparse` enabled because it is what turns ADTS input into raw
            // frames that the decoder can consume.
            "GST_PLUGIN_FEATURE_RANK": "atdec:NONE,avdec_aac:MAX"
        ]
        if fm.fileExists(atPath: scanner.path(percentEncoded: false)) {
            let path = scanner.path(percentEncoded: false)
            result["GST_PLUGIN_SCANNER"] = path
            result["GST_PLUGIN_SCANNER_1_0"] = path
        }
        return result
    }

    // MARK: - Framework installation helpers

    private static func removeQuarantineRecursively(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path(percentEncoded: false)]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Best effort.
        }
    }

    private static func cleanupStaleInstallArtifacts() {
        guard let children = try? fm.contentsOfDirectory(
            at: libraryRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix("Temp-") || name.hasPrefix("GStreamer.framework.new-") {
                try? fm.removeItem(at: child)
            }
        }
    }

    private static func isFrameworkValid(at framework: URL) -> Bool {
        let version10 = framework.appending(path: "Versions/1.0", directoryHint: .isDirectory)
        let required = [
            "lib/libgstvideo-1.0.0.dylib",
            "lib/libgstreamer-1.0.0.dylib",
            "lib/gstreamer-1.0/libgstcoreelements.dylib",
            "lib/gstreamer-1.0/libgstlibav.dylib",
            // MPEG-TS demuxing is needed by the HLS clips the launcher and
            // in-game browser play. It lives in the "restricted" codecs
            // component, which is easy to omit from a curated install.
            "lib/gstreamer-1.0/libgstmpegtsdemux.dylib",
            "libexec/gstreamer-1.0/gst-plugin-scanner"
        ]
        return required.allSatisfy { relative in
            fm.fileExists(atPath: version10.appending(path: relative).path(percentEncoded: false))
        }
    }

    private struct PayloadEntry {
        let name: String
        let url: URL
    }

    private static func payloadDirectories(in root: URL) throws -> [PayloadEntry] {
        let children = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var result: [PayloadEntry] = []
        for child in children where child.pathExtension == "pkg" {
            let payload = child.appending(path: "Payload", directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: payload.path(percentEncoded: false), isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            // e.g. "gstreamer-1.0-codecs-1.28.8-universal"
            result.append(PayloadEntry(name: child.deletingPathExtension().lastPathComponent, url: payload))
        }
        return result
    }

    private static func payload(in entries: [PayloadEntry], for component: String) -> URL? {
        let prefix = component + "-"
        return entries.first { entry in
            guard entry.name.hasPrefix(prefix) else { return false }
            // The component name is followed by a version number. This avoids
            // matching "gstreamer-1.0-codecs" against "gstreamer-1.0-codecs-gpl".
            return entry.name.dropFirst(prefix.count).first?.isNumber == true
        }?.url
    }

    private static func installFrameworkLink(at link: URL) throws {
        var target = frameworkURL.path(percentEncoded: false)
        if target.hasSuffix("/") {
            target.removeLast()
        }

        if let destination = try? fm.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false)) {
            if destination == target {
                return
            }
            try? fm.removeItem(at: link)
        } else if fm.fileExists(atPath: link.path(percentEncoded: false)) {
            // A real framework can be present when an upstream pre-patched
            // runtime served as the base. Replace it with the shared copy so
            // every bottle does not carry its own ~350 MB framework.
            try? fm.removeItem(at: link)
        }

        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: link.path(percentEncoded: false), withDestinationPath: target)
    }

    private static func ditto(_ source: URL, _ destination: URL) throws {
        try run("/usr/bin/ditto", [
            source.path(percentEncoded: false),
            destination.path(percentEncoded: false)
        ])
    }

    private static func existingRPaths(of url: URL) -> Set<String> {
        guard let output = try? run("/usr/bin/otool", ["-l", url.path(percentEncoded: false)]) else {
            return []
        }

        var result = Set<String>()
        var inRPath = false
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "cmd LC_RPATH" {
                inRPath = true
                continue
            }
            guard inRPath else { continue }

            if line.hasPrefix("path ") {
                let path = line.dropFirst("path ".count)
                    .split(separator: " ")
                    .first
                    .map(String.init) ?? ""
                result.insert(path)
                inRPath = false
            } else if line.hasPrefix("cmd ") {
                inRPath = false
            }
        }
        return result
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw WineGStreamerError.commandFailed(executable, -1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw WineGStreamerError.commandFailed(executable, process.terminationStatus, output)
        }
        return output
    }
}

public enum WineGStreamerError: LocalizedError {
    case integrityCheckFailed
    case invalidPackage(String)
    case invalidFramework
    case commandFailed(String, Int32, String)

    public var errorDescription: String? {
        switch self {
        case .integrityCheckFailed:
            return "The GStreamer package failed its integrity check."
        case .invalidPackage(let detail):
            return "The GStreamer package is invalid: \(detail)."
        case .invalidFramework:
            return "The extracted GStreamer framework is incomplete."
        case .commandFailed(let tool, let status, let output):
            return "\(tool) failed with status \(status): \(output)"
        }
    }
}
