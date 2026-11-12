//
//  WinemacClipCursorResetPatch.swift
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

/// Patches the `macdrv_ClipCursor` reset branch in Wine's winemac driver.
///
/// Wine < 11.10 returns early when `reset` is true, even though win32u has
/// already cleared the server-side clipping rectangle. The Cocoa side keeps
/// its confinement/event tap active, which can leave the cursor pinned at the
/// center of the screen after Cmd+Tab. The upstream fix makes reset fall
/// through to the normal "infinite clip rectangle" path.
public enum WinemacClipCursorResetPatch {
    public enum Result: Equatable, Sendable {
        case applied
        case alreadyApplied
        case reverted
        case notApplied
        case unsupported(String)
    }

    private static var fm: FileManager { FileManager.default }
    private static let logger = Logger(
        subsystem: "com.whisky.WhiskyKit",
        category: "WinemacClipCursorResetPatch"
    )
    private static let lock = NSLock()

    // `testl %r14d,%r14d; je ...` -> `testl %r14d,%r14d; jmp ...`
    private static let originalBranch = Data([0x45, 0x85, 0xF6, 0x74, 0x0E])
    private static let patchedBranch = Data([0x45, 0x85, 0xF6, 0xEB, 0x0E])
    private static let binaryRelativePath = "lib/wine/x86_64-unix/winemac.so"

    /// Whether the runtime version predates the upstream fix (Wine 11.10).
    public static func isAffected(runtimeVersion: String) -> Bool {
        let components = runtimeVersion
            .split(separator: ".")
            .compactMap { Int($0.prefix(while: { $0.isNumber })) }
        guard let major = components.first else { return false }
        let minor = components.count > 1 ? components[1] : 0
        return major < 11 || (major == 11 && minor < 10)
    }

    public static func isApplied(at runtimeRoot: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? Data(contentsOf: binaryURL(runtimeRoot)) else {
            return false
        }
        return occurrences(of: originalBranch, in: data) == 0
            && occurrences(of: patchedBranch, in: data) == 1
    }

    @discardableResult
    public static func apply(to runtimeRoot: URL) throws -> Result {
        lock.lock()
        defer { lock.unlock() }

        let url = binaryURL(runtimeRoot)
        guard let data = try? Data(contentsOf: url) else {
            return .unsupported("winemac.so not found")
        }

        let originalCount = occurrences(of: originalBranch, in: data)
        let patchedCount = occurrences(of: patchedBranch, in: data)
        if originalCount == 0, patchedCount == 1 {
            let backup = backupURL(for: url)
            try ensureBackupIfPossible(from: data, at: backup)
            return .alreadyApplied
        }
        guard originalCount == 1, patchedCount == 0 else {
            return .unsupported("unexpected winemac.so layout")
        }

        let backup = backupURL(for: url)
        if let backupData = try? Data(contentsOf: backup) {
            // Never keep a backup that cannot restore the original branch.
            if occurrences(of: originalBranch, in: backupData) != 1 {
                try? fm.removeItem(at: backup)
            }
        }
        if !fm.fileExists(atPath: backup.path(percentEncoded: false)) {
            try fm.copyItem(at: url, to: backup)
        }

        var patched = data
        guard let range = patched.range(of: originalBranch) else {
            return .unsupported("unexpected winemac.so layout")
        }
        patched.replaceSubrange(range, with: patchedBranch)

        let temp = tempURL(for: url)
        do {
            try patched.write(to: temp, options: .atomic)
            try fm.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: temp.path(percentEncoded: false)
            )
            try sign(temp)
            try verify(temp)
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }

        logger.info("Applied winemac ClipCursor reset fix at \(runtimeRoot.lastPathComponent, privacy: .public)")
        return .applied
    }

    @discardableResult
    public static func revert(from runtimeRoot: URL) throws -> Result {
        lock.lock()
        defer { lock.unlock() }

        let url = binaryURL(runtimeRoot)
        let backup = backupURL(for: url)
        guard fm.fileExists(atPath: backup.path(percentEncoded: false)) else {
            return .notApplied
        }

        let backupData = try Data(contentsOf: backup)
        guard occurrences(of: originalBranch, in: backupData) == 1,
              occurrences(of: patchedBranch, in: backupData) == 0 else {
            throw WinemacClipCursorResetPatchError.unsupportedLayout
        }

        let temp = tempURL(for: url)
        do {
            try fm.copyItem(at: backup, to: temp)
            try fm.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: temp.path(percentEncoded: false)
            )
            do {
                try verify(temp)
            } catch {
                // The copied signature should normally be valid. Re-sign as a
                // fallback so a successful revert never leaves the file
                // unloadable under Rosetta.
                try sign(temp)
                try verify(temp)
            }
            _ = try fm.replaceItemAt(url, withItemAt: temp)
            try? fm.removeItem(at: backup)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }

        logger.info("Reverted winemac ClipCursor reset fix at \(runtimeRoot.lastPathComponent, privacy: .public)")
        return .reverted
    }

    private static func binaryURL(_ runtimeRoot: URL) -> URL {
        runtimeRoot.appendingPathComponent(binaryRelativePath, isDirectory: false)
    }

    private static func backupURL(for binary: URL) -> URL {
        binary.appendingPathExtension("orig")
    }

    /// If the runtime was already patched without an app-managed backup (for
    /// example by a manual hot patch), reconstruct the original bytes so the
    /// option can still be turned off later. The reconstructed file is not
    /// signed; `revert` re-signs it if necessary.
    private static func ensureBackupIfPossible(from patchedData: Data, at backup: URL) throws {
        guard !fm.fileExists(atPath: backup.path(percentEncoded: false)) else { return }
        var original = patchedData
        guard let range = original.range(of: patchedBranch) else { return }
        original.replaceSubrange(range, with: originalBranch)
        try original.write(to: backup, options: .atomic)
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: backup.path(percentEncoded: false)
        )
    }

    private static func tempURL(for binary: URL) -> URL {
        binary
            .deletingLastPathComponent()
            .appendingPathComponent(".\(binary.lastPathComponent).\(UUID().uuidString).tmp")
    }

    private static func occurrences(of needle: Data, in data: Data) -> Int {
        var count = 0
        var searchStart = data.startIndex
        while searchStart < data.endIndex,
              let range = data.range(of: needle, options: [], in: searchStart..<data.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func sign(_ url: URL) throws {
        try runCodesign(["--force", "--sign", "-", url.path(percentEncoded: false)])
    }

    private static func verify(_ url: URL) throws {
        try runCodesign(["--verify", "--strict", url.path(percentEncoded: false)])
    }

    private static func runCodesign(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw WinemacClipCursorResetPatchError.codesignUnavailable(error.localizedDescription)
        }

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: outputData, encoding: .utf8) ?? ""
            throw WinemacClipCursorResetPatchError.codesignFailed(
                process.terminationStatus,
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

public enum WinemacClipCursorResetPatchError: LocalizedError, Sendable {
    case unsupportedLayout
    case codesignUnavailable(String)
    case codesignFailed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedLayout:
            return "The installed winemac.so has an unexpected layout."
        case .codesignUnavailable(let message):
            return "Unable to run codesign: \(message)"
        case .codesignFailed(let status, let output):
            return "codesign failed with status \(status): \(output)"
        }
    }
}
