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
import Combine
import SwiftUI
import WhiskyKit

@MainActor
final class KeyMacroToolbarCoordinator {
    static let shared = KeyMacroToolbarCoordinator()

    private(set) var isActive = false
    let newMacro = PassthroughSubject<Void, Never>()

    func activate() {
        isActive = true
    }

    func deactivate() {
        isActive = false
    }

    func requestNewMacro() {
        guard isActive else { return }
        newMacro.send()
    }
}

struct KeyMacroView: View {
    @ObservedObject var bottle: Bottle
    @StateObject private var service = KeyMacroService.shared

    @State private var selectedScriptID: UUID?
    @State private var captureTarget: CaptureTarget?
    @State private var pendingTrigger: PendingTrigger?
    @State private var captureAuthorizationIssue: CaptureAuthorizationIssue?

    private var store: BottleMacroStore {
        service.store(for: bottle)
    }

    private var isForegroundBottle: Bool {
        service.activeBottleURL == bottle.url.standardizedFileURL
    }

    private var bannerKind: PermissionBannerKind? {
        if !service.enabled || !store.settings.enabled {
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
                macroList
                    .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
                editor
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .background(
            MacroWindowSizer(minimumContentSize: NSSize(width: 820, height: 580))
                .frame(width: 0, height: 0)
        )
        .navigationTitle("keyMacros.title")
        .onAppear {
            KeyMacroToolbarCoordinator.shared.activate()
            service.start()
            ensureSelection()
        }
        .onDisappear {
            KeyMacroToolbarCoordinator.shared.deactivate()
        }
        .onReceive(KeyMacroToolbarCoordinator.shared.newMacro) { _ in
            addMacro()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Permissions are changed in System Settings. Refresh when the user
            // comes back instead of showing a second refresh button.
            service.refreshPermission()
        }
        .onChange(of: selectedScriptID) { _, newValue in
            store.selectScript(id: newValue)
        }
        .sheet(item: $captureTarget) { target in
            captureSheet(for: target.id)
                .onDisappear { captureTarget = nil }
        }
        .alert("keyMacros.error.triggerInUse.title", isPresented: Binding(
            get: { pendingTrigger != nil },
            set: { if !$0 { pendingTrigger = nil } }
        )) {
            Button("keyMacros.cancel", role: .cancel) {
                pendingTrigger = nil
            }
            Button("keyMacros.triggerConflict.confirm", role: .destructive) {
                if let pending = pendingTrigger {
                    applyTrigger(pending.trigger, to: pending.scriptID)
                }
                pendingTrigger = nil
            }
        } message: {
            if let pending = pendingTrigger {
                Text(String(
                    format: NSLocalizedString("keyMacros.triggerConflict.message", comment: ""),
                    pending.ownerName
                ))
            }
        }
    }

    private var macroList: some View {
        MacroListView(
            store: store,
            selection: $selectedScriptID,
            bottleName: bottle.settings.name,
            isForeground: isForegroundBottle,
            enabled: macroEnabledBinding,
            onRecordTrigger: beginCapture
        )
        .alert("keyMacros.permission.required.title", isPresented: Binding(
            get: { captureAuthorizationIssue != nil },
            set: { if !$0 { captureAuthorizationIssue = nil } }
        )) {
            if let issue = captureAuthorizationIssue {
                Button(issue.actionKey) {
                    handleCaptureAuthorizationAction(issue)
                    captureAuthorizationIssue = nil
                }
            }
            Button("keyMacros.cancel", role: .cancel) {
                captureAuthorizationIssue = nil
            }
        } message: {
            if let issue = captureAuthorizationIssue {
                Text(issue.messageKey)
            }
        }
    }

    private var macroEnabledBinding: Binding<Bool> {
        Binding(
            get: { service.enabled && store.settings.enabled },
            set: { enabled in
                service.enabled = enabled
                store.setEnabled(enabled)
            }
        )
    }

    private func addMacro() {
        let id = store.addScript(name: String(localized: "keyMacros.newName"))
        selectedScriptID = id
        store.selectScript(id: id)
    }

    private func applyTrigger(_ trigger: MacroTrigger, to scriptID: UUID) {
        guard store.setBinding(scriptID: scriptID, trigger: trigger) != nil else { return }
        selectedScriptID = scriptID
        store.selectScript(id: scriptID)
        captureTarget = nil
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
                    store.setEnabled(true)
                }
                .buttonStyle(.borderedProminent)
            case .permission:
                Button("keyMacros.permission.open") {
                    service.requestPermission()
                    service.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
            case .listener:
                Button("keyMacros.permission.inputMonitoring") {
                    service.openInputMonitoringSettings()
                }
                .buttonStyle(.borderedProminent)
            case nil:
                EmptyView()
            }
        }
        .padding(14)
        .background(bannerColor.opacity(0.11))
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
    private func captureSheet(for scriptID: UUID) -> some View {
        if store.script(id: scriptID) != nil {
            TriggerCaptureView(service: service) { trigger in
                if let owner = store.enabledBindingOwner(for: trigger, excluding: scriptID) {
                    pendingTrigger = PendingTrigger(
                        scriptID: scriptID,
                        trigger: trigger,
                        ownerName: owner.script.localizedDisplayName
                    )
                    return
                }
                applyTrigger(trigger, to: scriptID)
            }
        } else {
            VStack(spacing: 12) {
                Text("keyMacros.missing.title")
                Button("keyMacros.close") {
                    captureTarget = nil
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
        if let bannerKind {
            switch bannerKind {
            case .disabled:
                captureAuthorizationIssue = .macroDisabled
            case .permission:
                captureAuthorizationIssue = .accessibility
            case .listener:
                captureAuthorizationIssue = .inputMonitoring
            }
            return
        }

        selectedScriptID = scriptID
        store.selectScript(id: scriptID)
        captureTarget = CaptureTarget(id: scriptID)
    }

    private func handleCaptureAuthorizationAction(_ issue: CaptureAuthorizationIssue) {
        switch issue {
        case .macroDisabled:
            service.enabled = true
            store.setEnabled(true)
            service.requestPermission()
            service.openAccessibilitySettings()
        case .accessibility:
            service.requestPermission()
            service.openAccessibilitySettings()
        case .inputMonitoring:
            service.openInputMonitoringSettings()
        }
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

private struct CaptureTarget: Identifiable {
    let id: UUID
}

private struct PendingTrigger {
    let scriptID: UUID
    let trigger: MacroTrigger
    let ownerName: String
}

private enum CaptureAuthorizationIssue {
    case macroDisabled
    case accessibility
    case inputMonitoring

    var messageKey: LocalizedStringKey {
        switch self {
        case .macroDisabled:
            return "keyMacros.error.macroDisabled"
        case .accessibility:
            return "keyMacros.error.accessibility"
        case .inputMonitoring:
            return "keyMacros.error.inputMonitoring"
        }
    }

    var actionKey: LocalizedStringKey {
        switch self {
        case .macroDisabled:
            return "keyMacros.enabled"
        case .accessibility:
            return "keyMacros.permission.open"
        case .inputMonitoring:
            return "keyMacros.permission.inputMonitoring"
        }
    }
}

private struct MacroListView: View {
    @ObservedObject var store: BottleMacroStore
    @Binding var selection: UUID?
    let bottleName: String
    let isForeground: Bool
    @Binding var enabled: Bool
    let onRecordTrigger: (UUID) -> Void

    @State private var renameTarget: MacroScript?
    @State private var renameText = ""
    @State private var deleteTarget: MacroScript?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(14)

            List(selection: $selection) {
                ForEach(store.settings.scripts) { script in
                    MacroRow(
                        store: store,
                        script: script,
                        macrosEnabled: enabled,
                        onDelete: { deleteTarget = $0 }
                    )
                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                    .tag(script.id)
                    .contextMenu {
                        contextMenu(for: script)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .alert("keyMacros.delete.title", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("keyMacros.cancel", role: .cancel) {
                    deleteTarget = nil
                }
                Button("keyMacros.delete", role: .destructive) {
                    if let target = deleteTarget {
                        store.deleteScript(id: target.id)
                        if selection == target.id {
                            selection = store.settings.selectedScriptID
                        }
                    }
                    deleteTarget = nil
                }
            } message: {
                if let target = deleteTarget {
                    Text(String(
                        format: NSLocalizedString("keyMacros.delete.message", comment: ""),
                        target.localizedDisplayName
                    ))
                }
            }

            if store.lastSavedAt != nil {
                Divider()
                footer
                    .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                    Text(bottleName)
                        .font(.headline)
                        .lineLimit(1)
                    if isForeground {
                        Text("keyMacros.foreground")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }

                Text(String(
                    format: NSLocalizedString("keyMacros.list.count", comment: ""),
                    store.settings.scripts.count
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Toggle("keyMacros.enabled", isOn: $enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("keyMacros.enabled.all")
        }
    }

    @ViewBuilder
    private func contextMenu(for script: MacroScript) -> some View {
        let triggerAction: LocalizedStringKey = "keyMacros.recordTrigger"

        Button("keyMacros.rename") {
            renameTarget = script
            renameText = script.localizedDisplayName
        }
        Button(triggerAction) {
            selection = script.id
            onRecordTrigger(script.id)
        }
        if script.binding != nil {
            Button("keyMacros.clearTrigger") {
                store.clearBinding(scriptID: script.id)
            }
        }
        Divider()
        Button("keyMacros.duplicate") {
            selection = store.duplicateScript(
                id: script.id,
                nameSuffix: String(localized: "keyMacros.copySuffix")
            )
        }
        Button("keyMacros.delete", role: .destructive) {
            deleteTarget = script
        }
    }

    private var footer: some View {
        HStack {
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

private struct MacroRow: View {
    @ObservedObject var store: BottleMacroStore
    let script: MacroScript
    let macrosEnabled: Bool
    let onDelete: (MacroScript) -> Void

    @State private var isHovering = false

    private var binding: MacroTriggerBinding? {
        script.binding
    }

    private var effectivelyEnabled: Bool {
        macrosEnabled && binding?.enabled == true
    }

    private var stateColor: Color {
        guard binding != nil else { return .secondary.opacity(0.35) }
        return effectivelyEnabled ? .green : .secondary.opacity(0.55)
    }

    private var stateHelp: LocalizedStringKey {
        guard binding != nil else { return "keyMacros.unbound" }
        return effectivelyEnabled
            ? "keyMacros.trigger.enabledState"
            : "keyMacros.trigger.disabledState"
    }

    private var toggleHelp: LocalizedStringKey {
        macrosEnabled ? "keyMacros.trigger.toggle" : "keyMacros.globalDisabled"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(script.localizedDisplayName)
                    .lineLimit(1)

                if let binding {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingControls
                .frame(width: 66, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isHovering {
            HStack(spacing: 5) {
                if binding != nil {
                    Toggle("keyMacros.trigger.enabled", isOn: Binding(
                        get: { store.script(id: script.id)?.binding?.enabled ?? false },
                        set: { store.updateBinding(scriptID: script.id, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(!macrosEnabled)
                    .help(toggleHelp)
                } else {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .help("keyMacros.unbound")
                }

                Button(role: .destructive) {
                    onDelete(script)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("keyMacros.delete")
            }
        } else {
            Group {
                if binding == nil {
                    Circle()
                        .strokeBorder(stateColor, lineWidth: 1)
                } else {
                    Circle()
                        .fill(stateColor)
                }
            }
            .frame(width: 8, height: 8)
            .help(stateHelp)
        }
    }
}

private struct MacroEditorView: View {
    @ObservedObject var service: KeyMacroService
    @ObservedObject var store: BottleMacroStore
    let scriptID: UUID
    let onCaptureTrigger: () -> Void

    @State private var testError: String?
    @State private var savedFeedback = false
    @State private var saveFeedbackToken = UUID()

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
                    .frame(maxHeight: .infinity)
                Divider()
                triggerSection(script: script)
                    .layoutPriority(1)
            } else {
                ContentUnavailableView("keyMacros.missing.title", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("keyMacros.test.error.title", isPresented: Binding(
            get: { testError != nil },
            set: { if !$0 { testError = nil } }
        )) {
            Button("keyMacros.confirm") {
                testError = nil
            }
        } message: {
            Text(testError ?? "")
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
                    let token = UUID()
                    saveFeedbackToken = token
                    savedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        guard saveFeedbackToken == token else { return }
                        savedFeedback = false
                    }
                } label: {
                    Label {
                        Text(savedFeedback
                            ? LocalizedStringKey("keyMacros.savedNow")
                            : LocalizedStringKey("keyMacros.save"))
                    } icon: {
                        Image(systemName: savedFeedback
                            ? "checkmark.circle.fill"
                            : "square.and.arrow.down")
                    }
                    .foregroundStyle(savedFeedback ? .green : .primary)
                }
                Button {
                    service.test(script: script, store: store)
                    testError = service.lastError
                } label: {
                    Label("keyMacros.test", systemImage: "play.fill")
                }
                .disabled(service.macroRunning)
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
                .frame(minHeight: 120, maxHeight: .infinity)
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
        let triggerTitle: LocalizedStringKey = "keyMacros.recordTrigger"

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

            TriggerBindingRow(
                store: store,
                scriptID: script.id,
                binding: script.binding
            )
        }
        .padding(14)
    }
}

private struct TriggerBindingRow: View {
    @ObservedObject var store: BottleMacroStore
    let scriptID: UUID
    let binding: MacroTriggerBinding?

    private var mode: MacroTriggerMode {
        binding?.mode ?? .holdLoop
    }

    private var modeDetail: LocalizedStringKey {
        guard let binding else { return "keyMacros.trigger.unsetDetail" }
        return binding.mode.localizedDetail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("keyMacros.trigger.key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)

                    Group {
                        if let binding {
                            Text(binding.trigger.localizedDisplayName)
                        } else {
                            Text("keyMacros.trigger.unset")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    if let binding {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(binding.enabled ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(binding.enabled
                                ? LocalizedStringKey("keyMacros.trigger.enabledState")
                                : LocalizedStringKey("keyMacros.trigger.disabledState"))
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                GridRow {
                    Text("keyMacros.mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("keyMacros.mode", selection: Binding(
                        get: { mode },
                        set: { store.updateBinding(scriptID: scriptID, mode: $0) }
                    )) {
                        ForEach(MacroTriggerMode.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .leading)
                    .disabled(binding == nil)
                }
            }

            Text(modeDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("keyMacros.preventShortcut", isOn: Binding(
                get: { binding?.preventSystemShortcut ?? false },
                set: { store.updateBinding(scriptID: scriptID, preventSystemShortcut: $0) }
            ))
            .toggleStyle(.switch)
            .font(.caption)
            .disabled(binding == nil)

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
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
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

private struct MacroWindowSizer: NSViewRepresentable {
    let minimumContentSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.contentMinSize = minimumContentSize
            let current = window.contentView?.bounds.size ?? window.contentLayoutRect.size
            let target = NSSize(
                width: max(current.width, minimumContentSize.width),
                height: max(current.height, minimumContentSize.height)
            )
            guard target.width > current.width + 0.5 || target.height > current.height + 0.5 else { return }

            let contentRect = NSRect(origin: .zero, size: target)
            let frameSize = window.frameRect(forContentRect: contentRect).size
            var frame = window.frame
            // Keep the top edge in place when growing.
            frame.origin.y -= frameSize.height - frame.height
            frame.size = frameSize
            window.setFrame(frame, display: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Void) {
        DispatchQueue.main.async {
            nsView.window?.contentMinSize = NSSize(
                width: CGFloat(ViewWidth.large),
                height: 316
            )
        }
    }
}

// swiftlint:enable file_length
