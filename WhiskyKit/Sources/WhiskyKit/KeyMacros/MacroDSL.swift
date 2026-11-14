//
//  MacroDSL.swift
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
import Foundation

/// XMBC-style macro parser.
///
/// Supported tags (case-insensitive):
/// - `{WAITMS:n}` wait n milliseconds; `{WAIT:n}` wait n seconds
/// - `{HOLDMS:n}` hold the next key/click for n milliseconds; `{HOLD:n}` seconds
/// - `{LMB}` `{RMB}` `{MMB}` `{MB4}` `{MB5}` complete click
/// - `{LMBD}` `{LMBU}` (same for other buttons) separate down/up
/// - `{SHIFT}` `{CTRL}` `{ALT}` `{CMD}` modifier until `{CLEAR}`
/// - `{F1}`…`{F20}`, `{SPACE}`, `{ENTER}`, `{TAB}`, arrows and navigation keys
/// - ordinary characters are key presses; use `{{` and `}}` for literal braces
/// - `{WAITMS:100-200}` random wait
public enum MacroDSL {
    public static let defaultHoldMs: Double = 30

    public enum ParseError: Error, LocalizedError {
        case empty
        case unclosedTag
        case invalidTag(String)
        case missingArgument(String)
        case invalidArgument(String)
        case unsupportedKey(String)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "宏内容为空"
            case .unclosedTag:
                return "标签没有闭合"
            case .invalidTag(let tag):
                return "无效标签：\(tag)"
            case .missingArgument(let tag):
                return "标签缺少参数：\(tag)"
            case .invalidArgument(let tag):
                return "标签参数无效：\(tag)"
            case .unsupportedKey(let key):
                return "不支持的按键：\(key)"
            }
        }
    }

    // swiftlint:disable:next function_body_length
    public static func parse(_ text: String, defaultHoldMs: Double = MacroDSL.defaultHoldMs) throws -> [MacroItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }

        var items: [MacroItem] = []
        var pendingHoldMs: Double?
        var pendingFlags: UInt64 = 0

        enum TagKind { case click, down, release }

        func takeHoldMs() -> Double {
            let hold = pendingHoldMs ?? defaultHoldMs
            pendingHoldMs = nil
            return hold
        }

        func append(_ action: MacroAction, delaySeconds: Double = 0) {
            items.append(MacroItem(delaySeconds: max(0, delaySeconds), action: action))
        }

        func appendWait(seconds: Double) {
            guard seconds > 0 else { return }
            append(.wait, delaySeconds: seconds)
        }

        func appendClick(_ button: MacroMouseButton) {
            append(.mouseDown(button: button))
            append(.mouseUp(button: button), delaySeconds: takeHoldMs() / 1000.0)
        }

        func appendButton(_ button: MacroMouseButton, kind: TagKind) {
            switch kind {
            case .click:
                appendClick(button)
            case .down:
                append(.mouseDown(button: button))
                pendingHoldMs = nil
            case .release:
                append(.mouseUp(button: button))
                pendingHoldMs = nil
            }
        }

        func appendKeyPress(code: CGKeyCode, display: String, flags: UInt64) {
            let key = MacroKey(code: Int(code), display: display, flags: flags)
            append(.keyDown(key))
            append(.keyUp(key), delaySeconds: takeHoldMs() / 1000.0)
        }

        func parseNumber(_ raw: String, tag: String) throws -> Double {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw ParseError.missingArgument(tag) }
            if let number = Double(value) { return number }
            let parts = value.split(separator: "-", maxSplits: 1)
            if parts.count == 2, let low = Double(parts[0]), let high = Double(parts[1]), high >= low {
                return low + Double.random(in: 0...(high - low))
            }
            throw ParseError.invalidArgument(tag)
        }

        func buttonTag(_ name: String) -> (button: MacroMouseButton, kind: TagKind)? {
            let base: String
            let kind: TagKind
            if name.hasSuffix("D"), name.count > 1 {
                base = String(name.dropLast())
                kind = .down
            } else if name.hasSuffix("U"), name.count > 1 {
                base = String(name.dropLast())
                kind = .release
            } else {
                base = name
                kind = .click
            }
            switch base {
            case "LMB": return (.left, kind)
            case "RMB": return (.right, kind)
            case "MMB": return (.middle, kind)
            case "MB4": return (.button4, kind)
            case "MB5": return (.button5, kind)
            default: return nil
            }
        }

        // swiftlint:disable:next cyclomatic_complexity
        func handleTag(_ rawTag: String) throws {
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { throw ParseError.invalidTag(rawTag) }

            let colon = tag.firstIndex(of: ":")
            let name = String(colon.map { tag[tag.startIndex..<$0] } ?? tag[...]).uppercased()
            let argument = colon.map { String(tag[tag.index(after: $0)...]) }

            switch name {
            case "WAITMS":
                appendWait(seconds: max(0, try parseNumber(argument ?? "", tag: tag)) / 1000.0)
            case "WAIT":
                appendWait(seconds: max(0, try parseNumber(argument ?? "", tag: tag)))
            case "HOLDMS":
                pendingHoldMs = max(0, try parseNumber(argument ?? "", tag: tag))
            case "HOLD":
                pendingHoldMs = max(0, try parseNumber(argument ?? "", tag: tag)) * 1000.0
            case "CLEAR":
                pendingFlags = 0
            case "SHIFT":
                pendingFlags |= CGEventFlags.maskShift.rawValue
            case "CTRL", "CONTROL":
                pendingFlags |= CGEventFlags.maskControl.rawValue
            case "ALT", "OPTION":
                pendingFlags |= CGEventFlags.maskAlternate.rawValue
            case "CMD", "COMMAND", "WIN":
                pendingFlags |= CGEventFlags.maskCommand.rawValue
            case "VKC", "EXT":
                let raw = Int(try parseNumber(argument ?? "", tag: tag))
                appendKeyPress(code: CGKeyCode(raw), display: "vk_\(raw)", flags: pendingFlags)
            default:
                if let code = KeyCodeMap.keyCode(from: name) {
                    appendKeyPress(
                        code: code,
                        display: KeyCodeMap.displayName(for: code),
                        flags: pendingFlags
                    )
                    return
                }
                if let button = buttonTag(name) {
                    appendButton(button.button, kind: button.kind)
                    return
                }
                throw ParseError.invalidTag(rawTag)
            }
        }

        func handleCharacter(_ character: Character) throws {
            if character == "\n" || character == "\r" || character == "\t" { return }

            let display: String
            let code: CGKeyCode
            var needsShift = false

            if character == " " || character.isLetter || character.isNumber {
                display = character == " " ? "space" : String(character).lowercased()
                guard let mapped = KeyCodeMap.keyCode(from: display) else {
                    throw ParseError.unsupportedKey(String(character))
                }
                code = mapped
                needsShift = character.isUppercase && character.isLetter
            } else if let mapped = KeyCodeMap.punctuation(from: character) {
                display = String(character)
                code = mapped.code
                needsShift = mapped.shift
            } else {
                throw ParseError.unsupportedKey(String(character))
            }

            var flags = pendingFlags
            if needsShift {
                flags |= CGEventFlags.maskShift.rawValue
            }
            appendKeyPress(code: code, display: display, flags: flags)
        }

        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "{", index + 1 < characters.count, characters[index + 1] == "{" {
                try handleCharacter("{")
                index += 2
            } else if character == "}", index + 1 < characters.count, characters[index + 1] == "}" {
                try handleCharacter("}")
                index += 2
            } else if character == "{" {
                guard let close = characters[(index + 1)...].firstIndex(of: "}") else {
                    throw ParseError.unclosedTag
                }
                let tag = String(characters[(index + 1)..<close])
                index = close + 1
                try handleTag(tag)
            } else if character == "}" {
                throw ParseError.invalidTag("}")
            } else {
                try handleCharacter(character)
                index += 1
            }
        }

        return items
    }

    public static func durationSeconds(of items: [MacroItem]) -> Double {
        items.reduce(0) { $0 + $1.delaySeconds }
    }

    public static func durationText(of items: [MacroItem]) -> String {
        let total = durationSeconds(of: items)
        if total < 60 {
            return String(format: "%.1f 秒", total)
        }
        return String(format: "%.1f 分钟", total / 60)
    }
}
