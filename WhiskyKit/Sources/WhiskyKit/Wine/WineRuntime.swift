//
//  WineRuntime.swift
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

public struct WineRuntime: Identifiable, Hashable, Sendable {
    public enum RenderBackend: String, Hashable, Sendable {
        case dxmt
    }

    public struct ArchiveLayout: Hashable, Sendable {
        public var winePathInArchive: String?

        public init(winePathInArchive: String?) {
            self.winePathInArchive = winePathInArchive
        }
    }

    public var id: String
    public var displayName: String
    public var remoteURL: URL?
    public var renderBackend: RenderBackend?
    public var archive: ArchiveLayout

    public init(id: String, displayName: String, remoteURL: URL?, renderBackend: RenderBackend? = nil, archive: ArchiveLayout) {
        self.id = id
        self.displayName = displayName
        self.remoteURL = remoteURL
        self.renderBackend = renderBackend
        self.archive = archive
    }
}

public enum WineRuntimes {
    public static let whiskyDefaultId = "whisky"

    public static let all: [WineRuntime] = [
        WineRuntime(
            id: "11.4-dxmt-signed",
            displayName: "Wine 11.4 DXMT (signed)",
            remoteURL: URL(
                string:
                    "https://github.com/dawn-winery/dawn-signed/releases/download/wine-gcenx-11.4-osx64/" +
                    "wine-devel-11.4-osx64-signed.tar.xz"
            ),
            renderBackend: .dxmt,
            archive: .init(winePathInArchive: "wine-devel-11.4-osx64-signed/Contents/Resources/wine")
        ),
        WineRuntime(
            id: "11.0-dxmt-signed",
            displayName: "Wine 11.0 DXMT (signed)",
            remoteURL: URL(
                string:
                    "https://github.com/dawn-winery/dawn-signed/releases/download/wine-stable-gcenx-11.0-osx64/" +
                    "wine-stable-11.0-osx64-signed.tar.xz"
            ),
            renderBackend: .dxmt,
            archive: .init(winePathInArchive: "Wine Stable.app/Contents/Resources/wine")
        ),
        WineRuntime(
            id: "10.18-dxmt",
            displayName: "Wine 10.18 DXMT Experimental",
            remoteURL: URL(
                string:
                    "https://github.com/Gcenx/macOS_Wine_builds/releases/download/10.18/" +
                    "wine-devel-10.18-osx64.tar.xz"
            ),
            renderBackend: .dxmt,
            archive: .init(winePathInArchive: "Wine Devel.app/Contents/Resources/wine")
        ),
        WineRuntime(
            id: "9.9-dxmt",
            displayName: "Wine 9.9 DXMT",
            remoteURL: URL(string: "https://github.com/3Shain/wine/releases/download/v9.9-mingw/wine.tar.gz"),
            renderBackend: .dxmt,
            archive: .init(winePathInArchive: nil)
        ),
        // Keep WhiskyWine as the lowest priority runtime in the UI.
        WineRuntime(
            id: whiskyDefaultId,
            displayName: "WhiskyWine",
            remoteURL: nil,
            archive: .init(winePathInArchive: nil)
        )
    ]

    public static func runtime(id: String) -> WineRuntime? {
        return all.first(where: { $0.id == id })
    }
}
