//
//  MacroModels.swift
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

public enum MacroMouseButton: String, Codable, Sendable, CaseIterable, Identifiable {
    case left
    case right
    case middle
    case button4
    case button5

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .left: return "鼠标左键"
        case .right: return "鼠标右键"
        case .middle: return "鼠标中键"
        case .button4: return "鼠标侧键 4"
        case .button5: return "鼠标侧键 5"
        }
    }

    /// CGEvent `mouseEventButtonNumber`: 0 left, 1 right, 2 middle, 3 X1, 4 X2.
    public var buttonNumber: Int {
        switch self {
        case .left: return 0
        case .right: return 1
        case .middle: return 2
        case .button4: return 3
        case .button5: return 4
        }
    }

    public static func fromButtonNumber(_ number: Int) -> MacroMouseButton? {
        switch number {
        case 0: return .left
        case 1: return .right
        case 2: return .middle
        case 3: return .button4
        case 4: return .button5
        default: return nil
        }
    }
}

public struct MacroKey: Codable, Equatable, Sendable {
    public var code: Int
    public var display: String
    /// CGEventFlags raw value for modifiers such as Shift/Control/Option/Command.
    public var flags: UInt64

    public init(code: Int, display: String, flags: UInt64 = 0) {
        self.code = code
        self.display = display
        self.flags = flags
    }
}

public enum MacroAction: Codable, Equatable, Sendable {
    case wait
    case keyDown(MacroKey)
    case keyUp(MacroKey)
    case mouseDown(button: MacroMouseButton)
    case mouseUp(button: MacroMouseButton)
}

public struct MacroItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Delay in seconds before this action.
    public var delaySeconds: Double
    public var action: MacroAction

    public init(id: UUID = UUID(), delaySeconds: Double, action: MacroAction) {
        self.id = id
        self.delaySeconds = delaySeconds
        self.action = action
    }
}

public enum MacroTriggerMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case once
    case holdLoop
    case holdFinish
    case toggle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .once: return "按一次"
        case .holdLoop: return "按住循环，松开停止"
        case .holdFinish: return "按住循环，松开跑完这一遍"
        case .toggle: return "点一下开始/停止"
        }
    }

    public var detail: String {
        switch self {
        case .once: return "每次按下触发键执行一次宏。"
        case .holdLoop: return "按住触发键时循环执行，松开立即停止。"
        case .holdFinish: return "按住触发键时循环执行，松开后执行完当前这一遍再停止。"
        case .toggle: return "按一下开始循环，再按一下停止，适合鼠标侧键。"
        }
    }
}

public enum MacroTrigger: Codable, Hashable, Sendable {
    /// A keyboard key, with modifiers that must match exactly when the trigger starts.
    case key(code: UInt16, flags: UInt64)
    /// An extra mouse button. CGEvent button numbers 3 and 4 are side buttons.
    case mouse(buttonNumber: Int)

    public var displayName: String {
        switch self {
        case .key(let code, let flags):
            return Self.modifierPrefix(flags) + KeyCodeMap.displayName(for: CGKeyCode(code))
        case .mouse(let buttonNumber):
            return "鼠标键 \(buttonNumber + 1)"
        }
    }

    public var isModifierKey: Bool {
        guard case .key(let code, _) = self else { return false }
        return KeyCodeMap.isModifier(code: CGKeyCode(code))
    }

    public var keyCode: UInt16? {
        guard case .key(let code, _) = self else { return nil }
        return code
    }

    public var mouseButtonNumber: Int? {
        guard case .mouse(let number) = self else { return nil }
        return number
    }

    public var modifierFlags: UInt64 {
        guard case .key(_, let flags) = self else { return 0 }
        return flags
    }

    public func matchesKey(code: UInt16, flags: UInt64) -> Bool {
        guard case .key(let storedCode, let storedFlags) = self else { return false }
        return storedCode == code && storedFlags == flags
    }

    public func matchesKeyCode(_ code: UInt16) -> Bool {
        guard case .key(let storedCode, _) = self else { return false }
        return storedCode == code
    }

    public static func modifierPrefix(_ flags: UInt64) -> String {
        let value = CGEventFlags(rawValue: flags)
        var prefix = ""
        if value.contains(.maskControl) { prefix += "⌃" }
        if value.contains(.maskAlternate) { prefix += "⌥" }
        if value.contains(.maskShift) { prefix += "⇧" }
        if value.contains(.maskCommand) { prefix += "⌘" }
        return prefix
    }
}

public struct MacroTriggerBinding: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var trigger: MacroTrigger
    public var mode: MacroTriggerMode
    /// Experimental: swallow the trigger at the macOS layer and forward it to the game,
    /// so macOS system shortcuts do not also fire.
    public var preventSystemShortcut: Bool
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        trigger: MacroTrigger,
        mode: MacroTriggerMode = .holdLoop,
        preventSystemShortcut: Bool = false,
        enabled: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.mode = mode
        self.preventSystemShortcut = preventSystemShortcut
        self.enabled = enabled
    }
}

public struct MacroScript: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var text: String
    public var updatedAt: Date
    public var bindings: [MacroTriggerBinding]

    public init(
        id: UUID = UUID(),
        name: String,
        text: String,
        updatedAt: Date = Date(),
        bindings: [MacroTriggerBinding] = []
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.updatedAt = updatedAt
        self.bindings = bindings
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名宏" : trimmed
    }

    public var summary: String {
        guard let items = try? MacroDSL.parse(text) else { return "解析失败" }
        return "\(items.count) 个动作 · \(MacroDSL.durationText(of: items))"
    }
}

public struct BottleMacroSettings: Codable, Equatable, Sendable {
    public var version: Int
    public var enabled: Bool
    public var defaultHoldMs: Double
    public var scripts: [MacroScript]
    public var selectedScriptID: UUID?

    public init(
        version: Int = 1,
        enabled: Bool = true,
        defaultHoldMs: Double = MacroDSL.defaultHoldMs,
        scripts: [MacroScript] = [],
        selectedScriptID: UUID? = nil
    ) {
        self.version = version
        self.enabled = enabled
        self.defaultHoldMs = defaultHoldMs
        self.scripts = scripts
        self.selectedScriptID = selectedScriptID
    }
}
