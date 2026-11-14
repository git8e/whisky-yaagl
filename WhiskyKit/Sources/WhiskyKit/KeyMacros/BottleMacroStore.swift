//
//  BottleMacroStore.swift
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

import Combine
import Foundation
import os.log

/// Per-bottle key macro configuration. Stored next to the bottle's Metadata.plist.
@MainActor
public final class BottleMacroStore: ObservableObject {
    public let bottleURL: URL
    @Published public private(set) var settings: BottleMacroSettings

    private var pendingSave: Task<Void, Never>?
    @Published public private(set) var lastSavedAt: Date?

    public static func fileURL(forBottleURL bottleURL: URL) -> URL {
        bottleURL.appending(path: "Macros").appendingPathExtension("plist")
    }

    public init(bottleURL: URL) {
        self.bottleURL = bottleURL.standardizedFileURL
        let url = Self.fileURL(forBottleURL: self.bottleURL)
        do {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                let data = try Data(contentsOf: url)
                var decoded = try PropertyListDecoder().decode(BottleMacroSettings.self, from: data)
                if decoded.selectedScriptID == nil {
                    decoded.selectedScriptID = decoded.scripts.first?.id
                }
                self.settings = decoded
            } else {
                self.settings = BottleMacroSettings()
            }
        } catch {
            Logger.wineKit.error("Failed to load key macros from \(url.path): \(error)")
            self.settings = BottleMacroSettings()
        }

        if self.settings.scripts.isEmpty {
            let script = MacroScript(name: "", text: "")
            self.settings.scripts = [script]
            self.settings.selectedScriptID = script.id
        }
    }

    public var selectedScript: MacroScript? {
        guard let id = settings.selectedScriptID else { return nil }
        return settings.scripts.first(where: { $0.id == id })
    }

    public func script(id: UUID) -> MacroScript? {
        settings.scripts.first(where: { $0.id == id })
    }

    public func selectScript(id: UUID?) {
        settings.selectedScriptID = id
        saveSoon()
    }

    public func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
        saveSoon()
    }

    public func setDefaultHoldMs(_ value: Double) {
        settings.defaultHoldMs = min(max(value, 5), 500)
        saveSoon()
    }

    @discardableResult
    public func addScript(name: String = "New Macro", text: String = "") -> UUID {
        let script = MacroScript(name: uniqueName(base: name), text: text)
        settings.scripts.append(script)
        settings.selectedScriptID = script.id
        saveSoon()
        return script.id
    }

    @discardableResult
    public func duplicateScript(id: UUID, nameSuffix: String = " Copy") -> UUID? {
        guard let index = settings.scripts.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = settings.scripts[index]
        copy.id = UUID()
        copy.name = uniqueName(base: copy.name + nameSuffix)
        copy.updatedAt = Date()
        // A trigger key must be unique inside one container, so a duplicated
        // macro starts without a trigger and can be recorded independently.
        copy.binding = nil
        settings.scripts.insert(copy, at: index + 1)
        settings.selectedScriptID = copy.id
        saveSoon()
        return copy.id
    }

    public func deleteScript(id: UUID) {
        guard let index = settings.scripts.firstIndex(where: { $0.id == id }) else { return }
        settings.scripts.remove(at: index)
        if settings.scripts.isEmpty {
            let script = MacroScript(name: "", text: "")
            settings.scripts = [script]
            settings.selectedScriptID = script.id
        } else if settings.selectedScriptID == id {
            settings.selectedScriptID = settings.scripts[min(index, settings.scripts.count - 1)].id
        }
        saveSoon()
    }

    public func updateScriptText(id: UUID, text: String) {
        guard let index = settings.scripts.firstIndex(where: { $0.id == id }) else { return }
        guard settings.scripts[index].text != text else { return }
        settings.scripts[index].text = text
        settings.scripts[index].updatedAt = Date()
        saveSoon()
    }

    public func renameScript(id: UUID, name: String) {
        guard let index = settings.scripts.firstIndex(where: { $0.id == id }) else { return }
        guard settings.scripts[index].name != name else { return }
        settings.scripts[index].name = name
        settings.scripts[index].updatedAt = Date()
        saveSoon()
    }

    /// Replaces the macro's single trigger. Returns the binding id, or nil when
    /// another macro in this container already owns the trigger.
    @discardableResult
    public func setBinding(scriptID: UUID, trigger: MacroTrigger, mode: MacroTriggerMode = .holdLoop) -> UUID? {
        guard let scriptIndex = settings.scripts.firstIndex(where: { $0.id == scriptID }) else { return nil }
        guard !settings.scripts.contains(where: { script in
            script.id != scriptID && script.binding?.trigger == trigger
        }) else {
            return nil
        }

        if var binding = settings.scripts[scriptIndex].binding {
            binding.trigger = trigger
            settings.scripts[scriptIndex].binding = binding
            saveSoon()
            return binding.id
        }

        let binding = MacroTriggerBinding(trigger: trigger, mode: mode)
        settings.scripts[scriptIndex].binding = binding
        saveSoon()
        return binding.id
    }

    public func clearBinding(scriptID: UUID) {
        guard let scriptIndex = settings.scripts.firstIndex(where: { $0.id == scriptID }) else { return }
        guard settings.scripts[scriptIndex].binding != nil else { return }
        settings.scripts[scriptIndex].binding = nil
        saveSoon()
    }

    public func updateBinding(
        scriptID: UUID,
        mode: MacroTriggerMode? = nil,
        preventSystemShortcut: Bool? = nil,
        enabled: Bool? = nil
    ) {
        guard let scriptIndex = settings.scripts.firstIndex(where: { $0.id == scriptID }),
              var binding = settings.scripts[scriptIndex].binding else {
            return
        }
        if let mode {
            binding.mode = mode
        }
        if let preventSystemShortcut {
            binding.preventSystemShortcut = preventSystemShortcut
        }
        if let enabled {
            binding.enabled = enabled
        }
        settings.scripts[scriptIndex].binding = binding
        saveSoon()
    }

    public func binding(for trigger: MacroTrigger) -> (script: MacroScript, binding: MacroTriggerBinding)? {
        for script in settings.scripts {
            guard let binding = script.binding,
                  binding.enabled,
                  binding.trigger == trigger else {
                continue
            }
            return (script, binding)
        }
        return nil
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        writeNow()
    }

    private func uniqueName(base: String) -> String {
        let existing = Set(settings.scripts.map(\.name))
        if !existing.contains(base) { return base }
        var number = 2
        while existing.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }

    private func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    private func writeNow() {
        let url = Self.fileURL(forBottleURL: bottleURL)
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(settings)
            try data.write(to: url, options: .atomic)
            lastSavedAt = Date()
        } catch {
            Logger.wineKit.error("Failed to save key macros to \(url.path): \(error)")
        }
    }
}
