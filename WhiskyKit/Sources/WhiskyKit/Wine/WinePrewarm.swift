//
//  WinePrewarm.swift
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

private actor WinePrewarmCoordinator {
    static let shared = WinePrewarmCoordinator()
    private var started: Set<String> = []

    func begin(_ key: String) -> Bool {
        guard !started.contains(key) else { return false }
        started.insert(key)
        return true
    }
}

public extension Wine {
    /// Bring up wineserver/winedevice before the user presses Play.
    ///
    /// A cold Wine start costs around 5-7 seconds on Apple Silicon. Starting a
    /// tiny command while the pin grid is visible makes the actual game process
    /// appear in about a second instead. This is best-effort and runs at most
    /// once per bottle per Whisky session.
    static func prewarm(bottle: Bottle) async {
        let key = bottle.url.standardizedFileURL.path
        guard await WinePrewarmCoordinator.shared.begin(key) else { return }

        let task = Task.detached(priority: .utility) {
            _ = try? await Wine.runWine(
                ["cmd", "/c", "exit"],
                bottle: bottle,
                environment: ["WINEDEBUG": "-all"],
                log: false
            )
        }

        let timeout = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            task.cancel()
        }

        await task.value
        timeout.cancel()
    }
}
