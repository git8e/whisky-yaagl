//
//  KeyMacroService.swift
//  Whisky
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

// swiftlint:disable file_length

import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import Darwin
import Foundation
import WhiskyKit

enum KeyMacroPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    private static func openPrivacyPane(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// Reads another process's environment with `KERN_PROCARGS2`.
/// The macro event tap only gives us a macOS PID; Wine sets `WHISKY_BOTTLE_ID`
/// and `WINEPREFIX` in the environment of the game process.
enum ProcessEnvironment {
    // swiftlint:disable:next cyclomatic_complexity
    static func read(pid: pid_t) -> [String: String] {
        guard pid > 0 else { return [:] }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return [:]
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return [:]
        }

        guard buffer.count >= MemoryLayout<Int32>.size else { return [:] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc >= 0 else { return [:] }

        var index = MemoryLayout<Int32>.size

        // Executable path.
        while index < buffer.count && buffer[index] != 0 { index += 1 }
        while index < buffer.count && buffer[index] == 0 { index += 1 }

        // argv[0...argc-1].
        var remainingArguments = Int(argc)
        while remainingArguments > 0 && index < buffer.count {
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            index += 1
            remainingArguments -= 1
        }

        var result: [String: String] = [:]
        while index < buffer.count {
            let start = index
            while index < buffer.count && buffer[index] != 0 { index += 1 }
            if start < index,
               let entry = String(bytes: buffer[start..<index], encoding: .utf8),
               let separator = entry.firstIndex(of: "=") {
                let key = String(entry[..<separator])
                let value = String(entry[entry.index(after: separator)...])
                if !key.isEmpty {
                    result[key] = value
                }
            }
            index += 1
        }
        return result
    }
}

struct KeyMacroTarget {
    var pid: pid_t
    var bottleURL: URL
}

@MainActor
// swiftlint:disable:next type_body_length
final class KeyMacroService: ObservableObject {
    static let shared = KeyMacroService()

    private static let enabledDefaultsKey = "keyMacrosEnabled"

    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var monitorRunning = false
    @Published private(set) var activeBottleURL: URL?
    @Published private(set) var activeTargetPID: pid_t = 0
    @Published private(set) var macroRunning = false
    @Published private(set) var macroStatus: MacroRunner.Status = .idle
    @Published private(set) var captureActive = false
    @Published private(set) var lastError: String?

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
            if enabled {
                refreshPermission()
            } else {
                stopTap()
            }
        }
    }

    private let runner = MacroRunner()
    private var stores: [URL: BottleMacroStore] = [:]
    private var bottleCache: [pid_t: (url: URL, date: Date)] = [:]
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var captureHandler: ((MacroTrigger) -> Void)?
    private var pressedTriggers: [MacroTrigger: (binding: MacroTriggerBinding, pid: pid_t)] = [:]
    private var started = false

    private init() {
        if let stored = UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool {
            enabled = stored
        } else {
            enabled = true
        }
        runner.onStateChange = { [weak self] running, status in
            self?.macroRunning = running
            self?.macroStatus = status
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshActiveBottle()
            }
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermission()
            }
        }

        refreshPermission()
    }

    func shutdown() {
        for store in stores.values {
            store.saveNow()
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        stopTap()
        MacroHeldInputRegistry.shared.releaseAll()
    }

    // MARK: - Permissions and event tap

    func requestPermission() {
        KeyMacroPermission.request()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshPermission()
        }
    }

    func openAccessibilitySettings() {
        KeyMacroPermission.openSettings()
    }

    func openInputMonitoringSettings() {
        KeyMacroPermission.openInputMonitoringSettings()
    }

    func refreshPermission() {
        let trusted = KeyMacroPermission.isTrusted
        if permissionGranted != trusted {
            permissionGranted = trusted
        }

        if trusted && enabled {
            installTapIfNeeded()
        } else {
            stopTap()
        }
        refreshActiveBottle()
    }

    private func installTapIfNeeded() {
        guard tap == nil else { return }

        let mask = eventMask
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyMacroTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastError = String(localized: "keyMacros.error.eventTap")
            monitorRunning = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        monitorRunning = true
        lastError = nil
    }

    private func stopTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        monitorRunning = false
        captureHandler = nil
        captureActive = false
        pressedTriggers.removeAll()
        runner.stopAll()
    }

    private var eventMask: CGEventMask {
        let types: [CGEventType] = [
            .keyDown, .keyUp,
            .otherMouseDown, .otherMouseUp,
            .tapDisabledByTimeout, .tapDisabledByUserInput
        ]
        return types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
    }

    // MARK: - Bottle resolution

    func store(for bottle: Bottle) -> BottleMacroStore {
        let url = bottle.url.standardizedFileURL
        if let store = stores[url] {
            return store
        }
        let store = BottleMacroStore(bottleURL: url)
        stores[url] = store
        return store
    }

    private func store(forBottleURL url: URL) -> BottleMacroStore? {
        guard let bottle = BottleVM.shared.bottles.first(where: {
            $0.url.standardizedFileURL == url
        }) else {
            return nil
        }
        return store(for: bottle)
    }

    private func bottleURL(for pid: pid_t) -> URL? {
        if let cached = bottleCache[pid], Date().timeIntervalSince(cached.date) < 2 {
            return cached.url
        }

        let environment = ProcessEnvironment.read(pid: pid)
        guard let rawPath = environment["WHISKY_BOTTLE_ID"] ?? environment["WINEPREFIX"] else {
            return nil
        }

        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        guard BottleVM.shared.bottles.contains(where: { $0.url.standardizedFileURL == url }) else {
            return nil
        }

        bottleCache[pid] = (url, Date())
        return url
    }

    private func target(for event: CGEvent) -> KeyMacroTarget? {
        let eventPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        guard frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let frontPID = frontApp.processIdentifier
        guard frontPID > 0 else { return nil }

        if let frontBottle = bottleURL(for: frontPID) {
            let pid = eventPID > 0 ? eventPID : frontPID
            guard let targetBottle = bottleURL(for: pid), targetBottle == frontBottle else {
                return nil
            }
            return KeyMacroTarget(pid: pid, bottleURL: targetBottle)
        }

        // Some Wine games are not reported by NSWorkspace as the frontmost app.
        // Fall back to the event's target PID only when macOS marks it active.
        if eventPID > 0,
           let targetApp = NSRunningApplication(processIdentifier: eventPID),
           targetApp.isActive,
           let targetBottle = bottleURL(for: eventPID) {
            return KeyMacroTarget(pid: eventPID, bottleURL: targetBottle)
        }

        return nil
    }

    private func refreshActiveBottle() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        // Keep the last active game when the user brings Whisky's macro window forward,
        // but do not keep a macro running while the game is no longer foreground.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            pressedTriggers.removeAll()
            runner.stopAll()
            return
        }

        if let url = bottleURL(for: app.processIdentifier) {
            activeBottleURL = url
            activeTargetPID = app.processIdentifier
        } else {
            activeBottleURL = nil
            activeTargetPID = 0
            pressedTriggers.removeAll()
            runner.stopAll()
        }
    }

    // MARK: - Trigger capture

    @discardableResult
    func beginCapture(handler: @escaping (MacroTrigger) -> Void) -> Bool {
        guard enabled else {
            lastError = String(localized: "keyMacros.error.disabled")
            return false
        }
        guard permissionGranted else {
            lastError = String(localized: "keyMacros.error.permission")
            return false
        }
        refreshPermission()
        guard monitorRunning else {
            lastError = String(localized: "keyMacros.error.listener")
            return false
        }

        captureHandler = handler
        captureActive = true
        lastError = nil
        return true
    }

    func cancelCapture() {
        captureHandler = nil
        captureActive = false
    }

    // MARK: - Testing

    func test(script: MacroScript, store: BottleMacroStore) {
        guard activeTargetPID > 0 else {
            lastError = String(localized: "keyMacros.error.foreground")
            return
        }
        do {
            let items = try MacroDSL.parse(script.text, defaultHoldMs: store.settings.defaultHoldMs)
            guard !items.isEmpty else {
                lastError = String(localized: "keyMacros.error.emptyMacro")
                return
            }
            runner.runOnce(items: items, targetPID: activeTargetPID)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopMacro() {
        runner.stopAll()
        MacroHeldInputRegistry.shared.releaseAll()
    }

    // MARK: - Event handling

    // swiftlint:disable:next cyclomatic_complexity
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if MacroInputEmitter.isInjected(event) {
            return Unmanaged.passUnretained(event)
        }

        if let captureHandler {
            if type == .keyDown {
                guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                    return Unmanaged.passUnretained(event)
                }
                let trigger = keyTrigger(from: event)
                guard !trigger.isModifierKey else {
                    return Unmanaged.passUnretained(event)
                }
                self.captureHandler = nil
                captureActive = false
                captureHandler(trigger)
                return nil
            }

            if type == .otherMouseDown {
                let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                guard number >= 3 else {
                    return Unmanaged.passUnretained(event)
                }
                self.captureHandler = nil
                captureActive = false
                captureHandler(.mouse(buttonNumber: number))
                return nil
            }

            return Unmanaged.passUnretained(event)
        }

        guard enabled else { return Unmanaged.passUnretained(event) }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        case .otherMouseDown:
            return handleMouseDown(event)
        case .otherMouseUp:
            return handleMouseUp(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }

        let trigger = keyTrigger(from: event)
        guard !trigger.isModifierKey else {
            return Unmanaged.passUnretained(event)
        }
        guard let target = target(for: event),
              let store = store(forBottleURL: target.bottleURL),
              store.settings.enabled,
              let match = store.binding(for: trigger),
              pressedTriggers[trigger] == nil else {
            return Unmanaged.passUnretained(event)
        }

        activeBottleURL = target.bottleURL
        activeTargetPID = target.pid
        pressedTriggers[trigger] = (match.binding, target.pid)
        start(script: match.script, binding: match.binding, store: store, pid: target.pid)

        if match.binding.preventSystemShortcut {
            MacroInputEmitter.forward(event, to: target.pid)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let entry = pressedTriggers.first(where: { $0.key.matchesKeyCode(code) }) else {
            return Unmanaged.passUnretained(event)
        }

        pressedTriggers.removeValue(forKey: entry.key)
        runner.triggerReleased(mode: entry.value.binding.mode)

        if entry.value.binding.preventSystemShortcut {
            MacroInputEmitter.forward(event, to: entry.value.pid)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleMouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard number >= 3 else { return Unmanaged.passUnretained(event) }

        let trigger = MacroTrigger.mouse(buttonNumber: number)
        guard let target = target(for: event),
              let store = store(forBottleURL: target.bottleURL),
              store.settings.enabled,
              let match = store.binding(for: trigger),
              pressedTriggers[trigger] == nil else {
            return Unmanaged.passUnretained(event)
        }

        activeBottleURL = target.bottleURL
        activeTargetPID = target.pid
        pressedTriggers[trigger] = (match.binding, target.pid)
        start(script: match.script, binding: match.binding, store: store, pid: target.pid)

        if match.binding.preventSystemShortcut {
            MacroInputEmitter.forward(event, to: target.pid)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleMouseUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let trigger = MacroTrigger.mouse(buttonNumber: number)
        guard let entry = pressedTriggers.removeValue(forKey: trigger) else {
            return Unmanaged.passUnretained(event)
        }

        runner.triggerReleased(mode: entry.binding.mode)

        if entry.binding.preventSystemShortcut {
            MacroInputEmitter.forward(event, to: entry.pid)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func keyTrigger(from event: CGEvent) -> MacroTrigger {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        let flags = event.flags.intersection(relevant).rawValue
        return .key(code: code, flags: flags)
    }

    private func start(
        script: MacroScript,
        binding: MacroTriggerBinding,
        store: BottleMacroStore,
        pid: pid_t
    ) {
        let items: [MacroItem]
        do {
            items = try MacroDSL.parse(script.text, defaultHoldMs: store.settings.defaultHoldMs)
        } catch {
            lastError = error.localizedDescription
            return
        }

        guard !items.isEmpty else {
            lastError = String(localized: "keyMacros.error.emptyMacro")
            return
        }

        lastError = nil
        switch binding.mode {
        case .once:
            runner.runOnce(items: items, targetPID: pid)
        case .holdLoop, .holdFinish:
            runner.startHoldLoop(items: items, targetPID: pid)
        case .toggle:
            if runner.isRunning {
                runner.stopAll()
            } else {
                runner.startHoldLoop(items: items, targetPID: pid)
            }
        }
    }
}

private let keyMacroTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }
    let service = Unmanaged<KeyMacroService>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        service.handle(type: type, event: event)
    }
}

// swiftlint:enable file_length
