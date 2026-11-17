//
//  URL+Extensions.swift
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

extension String {
    public var esc: String {
        let esc = ["\\", "\"", "'", " ", "(", ")", "[", "]", "{", "}", "&", "|",
                   ";", "<", ">", "`", "$", "!", "*", "?", "#", "~", "="]
        var str = self
        for char in esc {
            str = str.replacingOccurrences(of: char, with: "\\" + char)
        }
        return str
    }
}

extension URL {
    public var esc: String {
        path.esc
    }

    public func prettyPath() -> String {
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: Bundle.main.bundleIdentifier ?? Bundle.whiskyBundleIdentifier, with: "whisky-yaagl")
            .replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
        return prettyPath
    }

    // NOT to be used for logic only as UI decoration
    public func prettyPath(_ bottle: Bottle) -> String {
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: bottle.url.path(percentEncoded: false), with: "")
            .replacingOccurrences(of: "/drive_c/", with: "C:\\")
            .replacingOccurrences(of: "/", with: "\\")
        return prettyPath
    }

    /// Compare two file URLs by their decoded, standardized path.
    ///
    /// `URL.path()` is percent-encoded by default while `path(percentEncoded: false)`
    /// is not. Mixing those two forms made pin lookups miss and created duplicate
    /// pins for games installed under folders with spaces.
    public func isSameFile(as other: URL) -> Bool {
        let lhs = standardizedFileURL.path(percentEncoded: false)
        let rhs = other.standardizedFileURL.path(percentEncoded: false)
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    // There is probably a better way to do this
    public func updateParentBottle(old: URL, new: URL) -> URL {
        let originalPath = path(percentEncoded: false)

        var oldBottlePath = old.path(percentEncoded: false)
        if oldBottlePath.last != "/" {
            oldBottlePath += "/"
        }

        var newBottlePath = new.path(percentEncoded: false)
        if newBottlePath.last != "/" {
            newBottlePath += "/"
        }

        let newPath = originalPath.replacingOccurrences(of: oldBottlePath,
                                                        with: newBottlePath)
        return URL(filePath: newPath)
    }
}

extension URL: @retroactive Identifiable {
    public var id: URL { self }
}
