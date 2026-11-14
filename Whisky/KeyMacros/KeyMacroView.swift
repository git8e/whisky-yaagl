//
//  KeyMacroView.swift
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
import SwiftUI
import WhiskyKit

struct KeyMacroView: View {
    @ObservedObject var bottle: Bottle
    @StateObject private var service = KeyMacroService.shared

    @State private var selectedScriptID: UUID?
    @State private var captureScriptID: UUID?
    @State private var showCapture = false
    @State private var triggerError: String?

    private var store: BottleMacroStore {
        service.store(for: bottle)
    }

    private var isForegroundBottle: Bool {
        service.activeBottleURL == bottle.url.standardizedFileURL
    }

    private var bannerKind: PermissionBannerKind? {
        if !service.enabled {
            return .disabled
        }
        if !service.permissionGranted {
            return .permission
        }
        if !service.monitorRunning {
            return .listener
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if bannerKind != nil {
                permissionBanner
            }

            HSplitView {
                MacroListView(
                    store: store,
                    selection: $selectedScriptID,
                    bottleName: bottle.settings.name,
                    isForeground: isForegroundBottle,
                    onRecordTrigger: beginCapture
                )
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)

                editor
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .navigationTitle("keyMacros.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { service.enabled },
                    set: { service.enabled = $0 }
                )) {
                    Label("keyMacros.enabled", systemImage: "keyboard")
                }
                .toggleStyle(.switch)
                .help("keyMacros.enabled")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    service.refreshPermission()
                } label: {
                    Label("keyMacros.permission.refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            service.start()
            ensureSelection()
        }
        .onChange(of: selectedScriptID) { _, newValue in
            store.selectScript(id: newValue)
        }
        .sheet(isPresented: $showCapture) {
            captureSheet
        }
        .alert("keyMacros.error.triggerInUse.title", isPresented: Binding(
            get: { triggerError != nil },
            set: { if !$0 { triggerError = nil } }
        )) {
            Button("keyMacros.confirm") {
                triggerError = nil
            }
        } message: {
            Text(triggerError ?? "")
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bannerIcon)
                .font(.title2)
                .foregroundStyle(bannerColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(bannerTitle)
                    .font(.headline)
                Text(bannerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = service.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            switch bannerKind {
            case .disabled:
                Button("keyMacros.enabled") {
                    service.enabled = true
                }
                .buttonStyle(.borderedProminent)
            case .permission:
                Button("keyMacros.permission.open") {
                    service.requestPermission()
                    service.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                Button("keyMacros.permission.refresh") {
                    service.refreshPermission()
                }
            case .listener:
                Button("keyMacros.permission.inputMonitoring") {
                    service.openInputMonitoringSettings()
                }
                .buttonStyle(.borderedProminent)
                Button("keyMacros.permission.refresh") {
                    service.refreshPermission()
                }
            case nil:
                EmptyView()
            }
        }
        .padding(14)
        .background(bannerColor.opacity(0.11))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var bannerIcon: String {
        switch bannerKind {
        case .disabled:
            return "keyboard.badge.ellipsis"
        case .permission:
            return "hand.raised.fill"
        case .listener:
            return "exclamationmark.triangle.fill"
        case nil:
            return "checkmark.circle.fill"
        }
    }

    private var bannerColor: Color {
        switch bannerKind {
        case .disabled:
            return .gray
        case .permission, .listener:
            return .orange
        case nil:
            return .green
        }
    }

    private var bannerTitle: LocalizedStringKey {
        switch bannerKind {
        case .disabled:
            return "keyMacros.permission.disabled.title"
        case .permission:
            return "keyMacros.permission.title"
        case .listener:
            return "keyMacros.permission.listener.title"
        case nil:
            return "keyMacros.permission.title"
        }
    }

    private var bannerDetail: LocalizedStringKey {
        switch bannerKind {
        case .disabled:
            return "keyMacros.permission.disabled.detail"
        case .permission:
            return "keyMacros.permission.detail"
        case .listener:
            return "keyMacros.permission.listener.detail"
        case nil:
            return "keyMacros.permission.detail"
        }
    }

    @ViewBuilder
    private var captureSheet: some View {
        if let scriptID = captureScriptID, store.script(id: scriptID) != nil {
            TriggerCaptureView(service: service) { trigger in
                guard store.setBinding(scriptID: scriptID, trigger: trigger) != nil else {
                    triggerError = String(localized: "keyMacros.error.triggerInUse")
                    return
                }
                selectedScriptID = scriptID
                store.selectScript(id: scriptID)
            }
        } else {
            VStack(spacing: 12) {
                Text("keyMacros.empty.title")
                Button("keyMacros.close") {
                    showCapture = false
                }
            }
            .padding(24)
        }
    }

    private var editor: some View {
        Group {
            if let selectedScriptID, store.script(id: selectedScriptID) != nil {
                MacroEditorView(
                    service: service,
                    store: store,
                    scriptID: selectedScriptID,
                    onCaptureTrigger: {
                        beginCapture(scriptID: selectedScriptID)
                    }
                )
            } else {
                ContentUnavailableView(
                    "keyMacros.empty.title",
                    systemImage: "keyboard",
                    description: Text("keyMacros.empty.detail")
                )
            }
        }
    }

    private func beginCapture(scriptID: UUID) {
        captureScriptID = scriptID
        showCapture = true
    }

    private func ensureSelection() {
        if let selectedScriptID, store.script(id: selectedScriptID) != nil {
            return
        }

        if let storedSelection = store.settings.selectedScriptID,
           store.script(id: storedSelection) != nil {
            selectedScriptID = storedSelection
        } else {
            selectedScriptID = store.settings.scripts.first?.id
            store.selectScript(id: selectedScriptID)
        }
    }
}

private enum PermissionBannerKind {
    case disabled
    case permission
    case listener
}

private struct MacroListView: View {
    @ObservedObject var store: BottleMacroStore
    @Binding var selection: UUID?
    let bottleName: String
    let isForeground: Bool
    let onRecordTrigger: (UUID) -> Void

    @State private var renameTarget: MacroScript?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(14)

            List(selection: $selection) {
                ForEach(store.settings.scripts) { script in
                    macroRow(script)
                        .tag(script.id)
                        .contextMenu {
                            contextMenu(for: script)
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()

            footer
                .padding(12)
        }
        .alert("keyMacros.rename.title", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("keyMacros.name", text: $renameText)
            Button("keyMacros.cancel", role: .cancel) {
                renameTarget = nil
            }
            Button("keyMacros.confirm") {
                if let renameTarget {
                    store.renameScript(id: renameTarget.id, name: renameText)
                }
                renameTarget = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("keyMacros.title")
                        .font(.headline)
                    if isForeground {
                        Text("keyMacros.foreground")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                Text(bottleName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(String(
                    format: NSLocalizedString("keyMacros.list.count", comment: ""),
                    store.settings.scripts.count
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                let id = store.addScript(name: String(localized: "keyMacros.newName"))
                selection = id
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("keyMacros.new")
        }
    }

    private func macroRow(_ script: MacroScript) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(script.localizedDisplayName)
                .lineLimit(1)

            if let binding = script.binding {
                Text(binding.trigger.localizedDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("keyMacros.unbound")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func contextMenu(for script: MacroScript) -> some View {
        let triggerAction: LocalizedStringKey = script.binding == nil
            ? "keyMacros.recordTrigger"
            : "keyMacros.rerecordTrigger"

        Button("keyMacros.rename") {
            renameTarget = script
            renameText = script.localizedDisplayName
        }
        Button(triggerAction) {
            selection = script.id
            onRecordTrigger(script.id)
        }
        Divider()
        Button("keyMacros.duplicate") {
            selection = store.duplicateScript(
                id: script.id,
                nameSuffix: String(localized: "keyMacros.copySuffix")
            )
        }
        Button("keyMacros.delete", role: .destructive) {
            store.deleteScript(id: script.id)
            if selection == script.id {
                selection = store.settings.scripts.first?.id
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("keyMacros.container.enabled", isOn: Binding(
                get: { store.settings.enabled },
                set: { store.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .font(.caption)

            Spacer()

            if let saved = store.lastSavedAt {
                Text(String(
                    format: NSLocalizedString("keyMacros.saved", comment: ""),
                    saved.formatted(date: .omitted, time: .shortened)
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MacroEditorView: View {
    @ObservedObject var service: KeyMacroService
    @ObservedObject var store: BottleMacroStore
    let scriptID: UUID
    let onCaptureTrigger: () -> Void

    private var script: MacroScript? {
        store.script(id: scriptID)
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { store.script(id: scriptID)?.text ?? "" },
            set: { store.updateScriptText(id: scriptID, text: $0) }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.script(id: scriptID)?.name ?? "" },
            set: { store.renameScript(id: scriptID, name: $0) }
        )
    }

    private var parsed: Result<[MacroItem], Error> {
        guard let script else {
            return .failure(MacroDSL.ParseError.empty)
        }
        return Result { try MacroDSL.parse(script.text, defaultHoldMs: store.settings.defaultHoldMs) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let script {
                header(script: script)
                Divider()
                scriptEditor(script: script)
                Divider()
                triggerSection(script: script)
            } else {
                ContentUnavailableView("keyMacros.missing.title", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func header(script: MacroScript) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                TextField("keyMacros.name.placeholder", text: nameBinding)
                    .font(.title3)
                    .textFieldStyle(.plain)
                Spacer()
                Button {
                    store.saveNow()
                } label: {
                    Label("keyMacros.save", systemImage: "square.and.arrow.down")
                }
                Button {
                    service.test(script: script, store: store)
                } label: {
                    Label("keyMacros.test", systemImage: "play.fill")
                }
                .disabled(service.activeTargetPID == 0)
                .help("keyMacros.test.help")
            }

            HStack(spacing: 8) {
                Label(
                    service.macroStatus.localizedLabel,
                    systemImage: service.macroRunning ? "waveform" : "pause.circle"
                )
                .font(.caption)
                    .foregroundStyle(service.macroRunning ? .blue : .secondary)
                if service.macroRunning {
                    Button("keyMacros.stop") {
                        service.stopMacro()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                Spacer()
                Text(script.localizedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    private func scriptEditor(script: MacroScript) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScriptTextView(text: textBinding)
                .frame(minHeight: 210, maxHeight: .infinity)
                .overlay {
                    if script.text.isEmpty {
                        Text("keyMacros.script.example")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }

            parseStatus

            HStack(spacing: 8) {
                Text("keyMacros.defaultHold")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { store.settings.defaultHoldMs },
                        set: { store.setDefaultHoldMs($0) }
                    ),
                    in: 5...200,
                    step: 5
                )
                Text("\(Int(store.settings.defaultHoldMs)) ms")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }

            Text(
                "{WAITMS:n} {WAIT:n} {HOLDMS:n} {HOLD:n} {LMB} {RMB} {MMB} {MB4} {MB5} "
                    + "{SHIFT} {CTRL} {ALT} {CMD} {CLEAR}"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    @ViewBuilder
    private var parseStatus: some View {
        switch parsed {
        case .success(let items):
            Label(
                String(
                    format: NSLocalizedString("keyMacros.parse.success", comment: ""),
                    items.count,
                    MacroDSL.durationText(of: items)
                ),
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func triggerSection(script: MacroScript) -> some View {
        let triggerTitle: LocalizedStringKey = script.binding == nil
            ? "keyMacros.recordTrigger"
            : "keyMacros.rerecordTrigger"

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("keyMacros.trigger.title")
                        .font(.headline)
                    Text("keyMacros.trigger.detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    onCaptureTrigger()
                } label: {
                    Label(triggerTitle, systemImage: "record.circle")
                }
            }

            if let binding = script.binding {
                TriggerBindingRow(
                    store: store,
                    scriptID: script.id,
                    binding: binding
                )
            } else {
                Text("keyMacros.trigger.empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(14)
    }
}

private struct TriggerBindingRow: View {
    @ObservedObject var store: BottleMacroStore
    let scriptID: UUID
    let binding: MacroTriggerBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(binding.trigger.localizedDisplayName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Spacer(minLength: 8)

                Toggle("keyMacros.trigger.enabled", isOn: Binding(
                    get: { binding.enabled },
                    set: { store.updateBinding(scriptID: scriptID, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .font(.caption)

                Button(role: .destructive) {
                    store.clearBinding(scriptID: scriptID)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("keyMacros.delete")
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("keyMacros.mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("keyMacros.mode", selection: Binding(
                    get: { binding.mode },
                    set: { store.updateBinding(scriptID: scriptID, mode: $0) }
                )) {
                    ForEach(MacroTriggerMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(binding.mode.localizedDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("keyMacros.preventShortcut", isOn: Binding(
                get: { binding.preventSystemShortcut },
                set: { store.updateBinding(scriptID: scriptID, preventSystemShortcut: $0) }
            ))
            .toggleStyle(.switch)
            .font(.caption)

            Text("keyMacros.preventShortcut.detail")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.secondary.opacity(0.18))
        }
    }
}

private struct TriggerCaptureView: View {
    @ObservedObject var service: KeyMacroService
    let onCapture: (MacroTrigger) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var started = false
    @State private var failureMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 38))
                .foregroundStyle(.blue)
            Text("keyMacros.capture.title")
                .font(.title2)
            Text(failureMessage ?? String(localized: "keyMacros.capture.waiting"))
                .foregroundStyle(.secondary)
            Text("keyMacros.capture.detail")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                Button("keyMacros.cancel") {
                    service.cancelCapture()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 450, height: 270)
        .onAppear {
            guard !started else { return }
            started = true
            let began = service.beginCapture { trigger in
                onCapture(trigger)
                dismiss()
            }
            if !began {
                failureMessage = service.lastError ?? String(localized: "keyMacros.capture.failed")
            }
        }
        .onDisappear {
            service.cancelCapture()
        }
    }
}

private extension MacroTrigger {
    var localizedDisplayName: String {
        switch self {
        case .key:
            return displayName
        case .mouse(let buttonNumber):
            return String(
                format: NSLocalizedString("keyMacros.mouseButton", comment: ""),
                buttonNumber + 1
            )
        }
    }
}

private extension MacroTriggerMode {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .once:
            return "keyMacros.mode.once"
        case .holdLoop:
            return "keyMacros.mode.holdLoop"
        case .holdFinish:
            return "keyMacros.mode.holdFinish"
        case .toggle:
            return "keyMacros.mode.toggle"
        }
    }

    var localizedDetail: LocalizedStringKey {
        switch self {
        case .once:
            return "keyMacros.mode.once.detail"
        case .holdLoop:
            return "keyMacros.mode.holdLoop.detail"
        case .holdFinish:
            return "keyMacros.mode.holdFinish.detail"
        case .toggle:
            return "keyMacros.mode.toggle.detail"
        }
    }
}

private extension MacroRunner.Status {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .idle:
            return "keyMacros.status.idle"
        case .stopped:
            return "keyMacros.status.stopped"
        case .runningLoop:
            return "keyMacros.status.runningLoop"
        case .runningOnce:
            return "keyMacros.status.runningOnce"
        case .emptyMacro:
            return "keyMacros.status.emptyMacro"
        }
    }
}

private extension MacroScript {
    var localizedDisplayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "keyMacros.untitled") : trimmed
    }

    var localizedSummary: String {
        guard let items = try? MacroDSL.parse(text) else {
            return String(localized: "keyMacros.parse.failed")
        }
        return String(
            format: NSLocalizedString("keyMacros.summary", comment: ""),
            items.count,
            MacroDSL.durationText(of: items)
        )
    }
}

/// NSTextView-backed editor with stable focus and smart punctuation disabled.
struct ScriptTextView: NSViewRepresentable {
    @Binding var text: String

    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.font = font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.delegate = context.coordinator
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selected
        }
        if textView.font != font {
            textView.font = font
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextView

        init(_ parent: ScriptTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }
}

// swiftlint:enable file_length
