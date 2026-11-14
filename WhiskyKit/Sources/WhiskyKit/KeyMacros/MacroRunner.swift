//
//  MacroRunner.swift
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

private final class MacroSharedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
}

@MainActor
public final class MacroRunner {
    public enum Status: Equatable, Sendable {
        case idle
        case stopped
        case runningLoop
        case runningOnce
        case emptyMacro

        public var label: String {
            switch self {
            case .idle: return "空闲"
            case .stopped: return "已停止"
            case .runningLoop: return "循环运行中"
            case .runningOnce: return "执行一次"
            case .emptyMacro: return "宏为空"
            }
        }
    }

    public var onStateChange: (@MainActor (Bool, Status) -> Void)?

    private let releaseFlag = MacroSharedFlag()
    private var runTask: Task<Void, Never>?
    private var runToken: UUID?

    public init() {}

    public var isRunning: Bool {
        runTask != nil
    }

    public func runOnce(items: [MacroItem], targetPID: pid_t) {
        startInternal(items: items, loop: false, targetPID: targetPID)
    }

    public func startHoldLoop(items: [MacroItem], targetPID: pid_t) {
        startInternal(items: items, loop: true, targetPID: targetPID)
    }

    public func triggerReleased(mode: MacroTriggerMode) {
        switch mode {
        case .once:
            break
        case .holdLoop:
            stopAll()
        case .holdFinish:
            releaseFlag.set()
        case .toggle:
            break
        }
    }

    public func stopAll() {
        guard runTask != nil else { return }
        runToken = nil
        releaseFlag.set()
        runTask?.cancel()
        onStateChange?(false, .stopped)
    }

    private func startInternal(items: [MacroItem], loop: Bool, targetPID: pid_t) {
        guard targetPID > 0 else {
            onStateChange?(false, .emptyMacro)
            return
        }
        guard !items.isEmpty else {
            onStateChange?(false, .emptyMacro)
            return
        }
        guard runTask == nil else { return }

        releaseFlag.reset()
        MacroHeldInputRegistry.shared.installExitHook()
        let token = UUID()
        runToken = token
        onStateChange?(true, loop ? .runningLoop : .runningOnce)

        let releaseFlag = self.releaseFlag
        let task = Task.detached(priority: .userInitiated) { [items, loop, targetPID, token] in
            var executor = Executor(targetPID: targetPID)
            defer {
                executor.cleanup()
                Task { @MainActor in
                    self.finishRun(token: token)
                }
            }

            do {
                if loop {
                    while !Task.isCancelled {
                        try await executor.run(items: items)
                        if releaseFlag.isSet { break }
                    }
                } else {
                    try await executor.run(items: items)
                }
            } catch {
                // Cancellation or execution failure; defer performs cleanup.
            }
        }
        runTask = task
    }

    private func finishRun(token: UUID) {
        let matched = runToken == token
        runTask = nil
        if matched {
            runToken = nil
            onStateChange?(false, .idle)
        } else {
            onStateChange?(false, .stopped)
        }
    }
}

private struct Executor {
    let targetPID: pid_t
    private var pressedKeys: [CGKeyCode: UInt64] = [:]
    private var heldButtons: Set<MacroMouseButton> = []

    init(targetPID: pid_t) {
        self.targetPID = targetPID
    }

    mutating func run(items: [MacroItem]) async throws {
        var nextNanoseconds = DispatchTime.now().uptimeNanoseconds

        func sleepUntil(_ target: UInt64) async throws {
            while true {
                let now = DispatchTime.now().uptimeNanoseconds
                if now >= target { return }
                try await Task.sleep(nanoseconds: target - now)
            }
        }

        for item in items {
            try Task.checkCancellation()

            if item.delaySeconds > 0 {
                nextNanoseconds = nextNanoseconds &+ UInt64(max(0, item.delaySeconds) * 1_000_000_000)
                try await sleepUntil(nextNanoseconds)
            }

            try Task.checkCancellation()

            switch item.action {
            case .wait:
                break
            case .keyDown(let key):
                let code = CGKeyCode(key.code)
                pressedKeys[code] = key.flags
                MacroHeldInputRegistry.shared.pressKey(code, flags: key.flags, to: targetPID)
            case .keyUp(let key):
                let code = CGKeyCode(key.code)
                pressedKeys.removeValue(forKey: code)
                MacroHeldInputRegistry.shared.releaseKey(code, flags: key.flags, to: targetPID)
            case .mouseDown(let button):
                heldButtons.insert(button)
                MacroHeldInputRegistry.shared.pressButton(button, to: targetPID)
            case .mouseUp(let button):
                heldButtons.remove(button)
                MacroHeldInputRegistry.shared.releaseButton(button, to: targetPID)
            }
        }
    }

    mutating func cleanup() {
        for button in heldButtons {
            MacroHeldInputRegistry.shared.releaseButton(button, to: targetPID)
        }
        heldButtons.removeAll(keepingCapacity: true)

        for (code, flags) in pressedKeys {
            MacroHeldInputRegistry.shared.releaseKey(code, flags: flags, to: targetPID)
        }
        pressedKeys.removeAll(keepingCapacity: true)
    }
}
