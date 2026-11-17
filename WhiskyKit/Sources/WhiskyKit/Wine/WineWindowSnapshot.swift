//
//  WineWindowSnapshot.swift
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

import CoreGraphics
import Darwin
import Foundation

/// Small helper around CoreGraphics window discovery.
///
/// Wine's Windows applications are hosted by macOS processes whose owner name is
/// `wine`. `wine start` exits as soon as it has handed the program to wineserver,
/// which can be several seconds before the actual launcher/game window appears.
/// Waiting for a real window is what keeps the launch spinner tied to something
/// the user can see.
public enum WineWindowSnapshot {
    public struct Snapshot: Sendable {
        public let windowIDs: Set<CGWindowID>

        public init(windowIDs: Set<CGWindowID>) {
            self.windowIDs = windowIDs
        }

        public var hasVisibleWindow: Bool {
            !windowIDs.isEmpty
        }
    }

    public static func capture(includeNonWine: Bool = false) -> Snapshot {
        Snapshot(windowIDs: visibleWindowIDs(includeNonWine: includeNonWine))
    }

    /// Wait until a window that was not present in `snapshot` is on screen.
    ///
    /// By default only windows owned by Wine are considered. Callers that are
    /// watching a launcher whose window belongs to a Windows executable can
    /// pass `includeNonWine: true`.
    ///
    /// Returns `true` when a new window appeared. The caller decides what a
    /// timeout means; this function only waits.
    public static func waitForNewWindow(
        since snapshot: Snapshot,
        timeout: TimeInterval = 25,
        includeNonWine: Bool = false
    ) async -> Bool {
        guard timeout > 0 else { return false }
        let deadline = Date().addingTimeInterval(timeout)

        while !Task.isCancelled && Date() < deadline {
            if !visibleWindowIDs(includeNonWine: includeNonWine)
                .subtracting(snapshot.windowIDs).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return !visibleWindowIDs(includeNonWine: includeNonWine)
            .subtracting(snapshot.windowIDs).isEmpty
    }

    /// Wait for a new visible Wine window and return the PID that owns it.
    /// Used to activate installer windows that `wine start` opens behind the
    /// current app.
    public static func waitForNewWindowOwnerPID(
        since snapshot: Snapshot,
        timeout: TimeInterval = 25
    ) async -> pid_t? {
        guard timeout > 0 else { return newWindowOwnerPID(since: snapshot) }
        let deadline = Date().addingTimeInterval(timeout)

        while !Task.isCancelled && Date() < deadline {
            if let pid = newWindowOwnerPID(since: snapshot) {
                return pid
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return newWindowOwnerPID(since: snapshot)
    }

    private static func newWindowOwnerPID(since snapshot: Snapshot) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner.lowercased().contains("wine"),
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  !snapshot.windowIDs.contains(CGWindowID(number.uint32Value)) else {
                continue
            }

            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            guard layer == 0 else { continue }

            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            guard width >= 120, height >= 90 else { continue }

            if let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value {
                return pid
            }
        }

        return nil
    }

    private static func visibleWindowIDs(includeNonWine: Bool = false) -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: Set<CGWindowID> = []
        for window in windows {
            if !includeNonWine {
                guard let owner = window[kCGWindowOwnerName as String] as? String,
                      owner.lowercased().contains("wine") else {
                    continue
                }
            }

            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            guard layer == 0 else { continue }

            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            guard width >= 120, height >= 90 else { continue }

            guard let number = window[kCGWindowNumber as String] as? NSNumber else { continue }
            result.insert(CGWindowID(number.uint32Value))
        }

        return result
    }
}
