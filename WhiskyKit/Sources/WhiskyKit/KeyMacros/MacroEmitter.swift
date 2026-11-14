//
//  MacroEmitter.swift
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

/// Sends macro input to a specific Wine process instead of the global HID stream.
public enum MacroInputEmitter {
    /// Marker stored in `eventSourceUserData` so the event tap can ignore its own output.
    public static let injectionUserData: Int64 = 0x5748_594D // "WHYM"

    public static func currentMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    public static func postKey(code: CGKeyCode, down: Bool, flags: UInt64, to pid: pid_t) {
        guard pid > 0 else { return }
        guard let event = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .hidSystemState),
            virtualKey: code,
            keyDown: down
        ) else { return }

        if flags != 0 {
            event.flags = CGEventFlags(rawValue: flags)
        }
        event.setIntegerValueField(.eventSourceUserData, value: injectionUserData)
        event.postToPid(pid)
    }

    public static func postMouse(down: Bool, button: MacroMouseButton, to pid: pid_t) {
        guard pid > 0 else { return }
        let location = currentMouseLocation()
        let source = CGEventSource(stateID: .hidSystemState)

        let type: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case .left:
            type = down ? .leftMouseDown : .leftMouseUp
            cgButton = .left
        case .right:
            type = down ? .rightMouseDown : .rightMouseUp
            cgButton = .right
        case .middle:
            type = down ? .otherMouseDown : .otherMouseUp
            cgButton = .center
        case .button4, .button5:
            type = down ? .otherMouseDown : .otherMouseUp
            cgButton = .center
        }

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: cgButton
        ) else { return }

        if button == .button4 || button == .button5 {
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.buttonNumber))
        }
        event.setIntegerValueField(.eventSourceUserData, value: injectionUserData)
        event.postToPid(pid)
    }

    /// Forward the original observed event to the same process. Used by the optional
    /// "prevent macOS system shortcut" mode.
    public static func forward(_ event: CGEvent, to pid: pid_t) {
        guard pid > 0, let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: injectionUserData)
        copy.postToPid(pid)
    }

    public static func isInjected(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == injectionUserData
    }
}

/// Tracks held inputs so quitting or stopping a macro does not leave keys/buttons stuck.
public final class MacroHeldInputRegistry: @unchecked Sendable {
    public static let shared = MacroHeldInputRegistry()

    private struct Key: Hashable {
        var code: CGKeyCode
        var pid: pid_t
    }

    private struct Button: Hashable {
        var button: MacroMouseButton
        var pid: pid_t
    }

    private let lock = NSLock()
    private var keys: [Key: UInt64] = [:]
    private var buttons: Set<Button> = []
    private var exitHookInstalled = false

    private init() {}

    public func installExitHook() {
        lock.lock()
        let needsInstall = !exitHookInstalled
        exitHookInstalled = true
        lock.unlock()
        guard needsInstall else { return }
        atexit {
            MacroHeldInputRegistry.shared.releaseAll()
        }
    }

    public func pressKey(_ code: CGKeyCode, flags: UInt64, to pid: pid_t) {
        let key = Key(code: code, pid: pid)
        lock.lock()
        keys[key] = flags
        lock.unlock()
        MacroInputEmitter.postKey(code: code, down: true, flags: flags, to: pid)
    }

    public func releaseKey(_ code: CGKeyCode, flags: UInt64, to pid: pid_t) {
        let key = Key(code: code, pid: pid)
        lock.lock()
        keys.removeValue(forKey: key)
        lock.unlock()
        MacroInputEmitter.postKey(code: code, down: false, flags: flags, to: pid)
    }

    public func pressButton(_ button: MacroMouseButton, to pid: pid_t) {
        let key = Button(button: button, pid: pid)
        lock.lock()
        buttons.insert(key)
        lock.unlock()
        MacroInputEmitter.postMouse(down: true, button: button, to: pid)
    }

    public func releaseButton(_ button: MacroMouseButton, to pid: pid_t) {
        let key = Button(button: button, pid: pid)
        lock.lock()
        buttons.remove(key)
        lock.unlock()
        MacroInputEmitter.postMouse(down: false, button: button, to: pid)
    }

    public func releaseAll() {
        lock.lock()
        let heldKeys = keys
        let heldButtons = buttons
        keys.removeAll()
        buttons.removeAll()
        lock.unlock()

        for (key, flags) in heldKeys {
            MacroInputEmitter.postKey(code: key.code, down: false, flags: flags, to: key.pid)
        }
        for key in heldButtons {
            MacroInputEmitter.postMouse(down: false, button: key.button, to: key.pid)
        }
    }
}
