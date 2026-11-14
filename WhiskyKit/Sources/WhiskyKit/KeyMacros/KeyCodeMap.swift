//
//  KeyCodeMap.swift
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

import Carbon
import CoreGraphics
import Foundation

enum KeyCodeMap {
    static func isModifier(code: CGKeyCode) -> Bool {
        switch Int(code) {
        case kVK_Shift, kVK_RightShift,
             kVK_Control, kVK_RightControl,
             kVK_Command, kVK_RightCommand,
             kVK_Option, kVK_RightOption,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func displayName(for code: CGKeyCode) -> String {
        switch Int(code) {
        case kVK_Shift: return "Shift"
        case kVK_RightShift: return "右 Shift"
        case kVK_Control: return "Control"
        case kVK_RightControl: return "右 Control"
        case kVK_Command: return "Command"
        case kVK_RightCommand: return "右 Command"
        case kVK_Option: return "Option"
        case kVK_RightOption: return "右 Option"
        case kVK_CapsLock: return "Caps Lock"
        case kVK_Function: return "Fn"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"

        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"

        default:
            return "键码 \(Int(code))"
        }
    }

    // US layout character to virtual keycode and shift requirement.
    // `{` and `}` are reserved by the macro DSL.
    // swiftlint:disable:next cyclomatic_complexity
    static func punctuation(from character: Character) -> (code: CGKeyCode, shift: Bool)? {
        switch character {
        case "=": return (CGKeyCode(kVK_ANSI_Equal), false)
        case "+": return (CGKeyCode(kVK_ANSI_Equal), true)
        case "-": return (CGKeyCode(kVK_ANSI_Minus), false)
        case "_": return (CGKeyCode(kVK_ANSI_Minus), true)
        case "[": return (CGKeyCode(kVK_ANSI_LeftBracket), false)
        case "{": return (CGKeyCode(kVK_ANSI_LeftBracket), true)
        case "]": return (CGKeyCode(kVK_ANSI_RightBracket), false)
        case "}": return (CGKeyCode(kVK_ANSI_RightBracket), true)
        case ";": return (CGKeyCode(kVK_ANSI_Semicolon), false)
        case ":": return (CGKeyCode(kVK_ANSI_Semicolon), true)
        case "'": return (CGKeyCode(kVK_ANSI_Quote), false)
        case "\"": return (CGKeyCode(kVK_ANSI_Quote), true)
        case ",": return (CGKeyCode(kVK_ANSI_Comma), false)
        case "<": return (CGKeyCode(kVK_ANSI_Comma), true)
        case ".": return (CGKeyCode(kVK_ANSI_Period), false)
        case ">": return (CGKeyCode(kVK_ANSI_Period), true)
        case "/": return (CGKeyCode(kVK_ANSI_Slash), false)
        case "?": return (CGKeyCode(kVK_ANSI_Slash), true)
        case "\\": return (CGKeyCode(kVK_ANSI_Backslash), false)
        case "|": return (CGKeyCode(kVK_ANSI_Backslash), true)
        case "`": return (CGKeyCode(kVK_ANSI_Grave), false)
        case "~": return (CGKeyCode(kVK_ANSI_Grave), true)
        case "!": return (CGKeyCode(kVK_ANSI_1), true)
        case "@": return (CGKeyCode(kVK_ANSI_2), true)
        case "#": return (CGKeyCode(kVK_ANSI_3), true)
        case "$": return (CGKeyCode(kVK_ANSI_4), true)
        case "%": return (CGKeyCode(kVK_ANSI_5), true)
        case "^": return (CGKeyCode(kVK_ANSI_6), true)
        case "&": return (CGKeyCode(kVK_ANSI_7), true)
        case "*": return (CGKeyCode(kVK_ANSI_8), true)
        case "(": return (CGKeyCode(kVK_ANSI_9), true)
        case ")": return (CGKeyCode(kVK_ANSI_0), true)
        default: return nil
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func keyCode(from displayOrVK: String) -> CGKeyCode? {
        let value = displayOrVK.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("vk_"), let number = Int(value.dropFirst(3)) {
            return CGKeyCode(number)
        }

        switch value {
        case "shift": return CGKeyCode(kVK_Shift)
        case "rshift": return CGKeyCode(kVK_RightShift)
        case "ctrl": return CGKeyCode(kVK_Control)
        case "rctrl": return CGKeyCode(kVK_RightControl)
        case "cmd": return CGKeyCode(kVK_Command)
        case "rcmd": return CGKeyCode(kVK_RightCommand)
        case "opt": return CGKeyCode(kVK_Option)
        case "ropt": return CGKeyCode(kVK_RightOption)
        case "space": return CGKeyCode(kVK_Space)
        case "enter", "return": return CGKeyCode(kVK_Return)
        case "tab": return CGKeyCode(kVK_Tab)
        case "backspace": return CGKeyCode(kVK_Delete)
        case "esc", "escape": return CGKeyCode(kVK_Escape)
        case "delete": return CGKeyCode(kVK_ForwardDelete)
        case "home": return CGKeyCode(kVK_Home)
        case "end": return CGKeyCode(kVK_End)
        case "pageup": return CGKeyCode(kVK_PageUp)
        case "pagedown": return CGKeyCode(kVK_PageDown)
        case "left": return CGKeyCode(kVK_LeftArrow)
        case "right": return CGKeyCode(kVK_RightArrow)
        case "up": return CGKeyCode(kVK_UpArrow)
        case "down": return CGKeyCode(kVK_DownArrow)
        case "f1": return CGKeyCode(kVK_F1)
        case "f2": return CGKeyCode(kVK_F2)
        case "f3": return CGKeyCode(kVK_F3)
        case "f4": return CGKeyCode(kVK_F4)
        case "f5": return CGKeyCode(kVK_F5)
        case "f6": return CGKeyCode(kVK_F6)
        case "f7": return CGKeyCode(kVK_F7)
        case "f8": return CGKeyCode(kVK_F8)
        case "f9": return CGKeyCode(kVK_F9)
        case "f10": return CGKeyCode(kVK_F10)
        case "f11": return CGKeyCode(kVK_F11)
        case "f12": return CGKeyCode(kVK_F12)
        case "f13": return CGKeyCode(kVK_F13)
        case "f14": return CGKeyCode(kVK_F14)
        case "f15": return CGKeyCode(kVK_F15)
        case "f16": return CGKeyCode(kVK_F16)
        case "f17": return CGKeyCode(kVK_F17)
        case "f18": return CGKeyCode(kVK_F18)
        case "f19": return CGKeyCode(kVK_F19)
        case "f20": return CGKeyCode(kVK_F20)

        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)

        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)

        default: return nil
        }
    }
}
