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

struct KeyMacroCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("按键宏") {
                openWindow(id: "keyMacros")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }
}

struct KeyMacroView: View {
    @StateObject private var service = KeyMacroService.shared
    @EnvironmentObject private var bottleVM: BottleVM

    @State private var selectedBottleURL: URL?
    @State private var selectedScriptID: UUID?
    @State private var captureScriptID: UUID?
    @State private var showCapture = false

    private var selectedBottle: Bottle? {
        bottleVM.bottles.first { $0.url.standardizedFileURL == selectedBottleURL }
    }

    private var selectedStore: BottleMacroStore? {
        guard let selectedBottle else { return nil }
        return service.store(for: selectedBottle)
    }

    private var activeBottleName: String? {
        guard let active = service.activeBottleURL else { return nil }
        return bottleVM.bottles.first(where: { $0.url.standardizedFileURL == active })?.settings.name
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 290)

            macroList
                .frame(minWidth: 230, idealWidth: 260, maxWidth: 330)

            editor
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1_000, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    service.refreshPermission()
                } label: {
                    Label("刷新权限", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            service.start()
            if selectedBottleURL == nil {
                selectedBottleURL = service.requestedBottleURL
                    ?? service.activeBottleURL
                    ?? bottleVM.bottles.first?.url.standardizedFileURL
                service.requestedBottleURL = nil
            }
            ensureSelection()
        }
        .onChange(of: service.activeBottleURL) { _, newValue in
            guard let newValue,
                  bottleVM.bottles.contains(where: { $0.url.standardizedFileURL == newValue }) else {
                return
            }
            selectedBottleURL = newValue
            ensureSelection()
        }
        .onChange(of: service.requestedBottleURL) { _, newValue in
            guard let newValue else { return }
            selectedBottleURL = newValue
            ensureSelection()
            service.requestedBottleURL = nil
        }
        .onChange(of: selectedBottleURL) { _, _ in
            ensureSelection()
        }
        .onChange(of: selectedScriptID) { _, newValue in
            selectedStore?.selectScript(id: newValue)
        }
        .sheet(isPresented: $showCapture) {
            if let store = selectedStore, let scriptID = captureScriptID {
                TriggerCaptureView(service: service) { trigger in
                    if store.addBinding(scriptID: scriptID, trigger: trigger) != nil {
                        selectedScriptID = scriptID
                    } else {
                        service.cancelCapture()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("没有可编辑的宏。")
                    Button("关闭") { showCapture = false }
                }
                .padding(24)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("容器")
                    .font(.headline)
                Text("每个容器单独保存自己的按键宏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)

            List(selection: $selectedBottleURL) {
                ForEach(bottleVM.bottles) { bottle in
                    BottleMacroRow(
                        bottle: bottle,
                        isActive: service.activeBottleURL == bottle.url.standardizedFileURL
                    )
                    .tag(bottle.url.standardizedFileURL)
                }
            }
            .listStyle(.sidebar)

            Divider()

            permissionPanel
                .padding(14)
        }
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: service.monitorRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(service.monitorRunning ? .green : .orange)
                Text(service.monitorRunning ? "事件监听已启用" : "事件监听未启用")
                    .font(.caption)
                    .bold()
            }

            Toggle("启用按键宏", isOn: Binding(
                get: { service.enabled },
                set: { service.enabled = $0 }
            ))
            .toggleStyle(.switch)

            if !service.permissionGranted {
                Text("需要 macOS 辅助功能权限才能读取按键并把宏发送到游戏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("打开辅助功能授权") {
                    service.requestPermission()
                }
                .controlSize(.small)
            } else if let activeBottleName {
                Text("当前前台游戏：\(activeBottleName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("让 Wine 游戏窗口位于前台后，宏会跟随该容器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = service.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var macroList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let store = selectedStore {
                MacroListView(
                    store: store,
                    selection: $selectedScriptID,
                    onAddTrigger: { scriptID in
                        captureScriptID = scriptID
                        showCapture = true
                    }
                )
            } else {
                ContentUnavailableView(
                    "选择容器",
                    systemImage: "shippingbox",
                    description: Text("左侧选择一个容器后编辑它的按键宏。")
                )
            }
        }
    }

    private var editor: some View {
        Group {
            if let store = selectedStore, let selectedScriptID, store.script(id: selectedScriptID) != nil {
                MacroEditorView(
                    service: service,
                    store: store,
                    scriptID: selectedScriptID,
                    onCaptureTrigger: {
                        captureScriptID = selectedScriptID
                        showCapture = true
                    }
                )
            } else {
                ContentUnavailableView(
                    "选择宏",
                    systemImage: "keyboard",
                    description: Text("新建或选择一个宏后开始编辑。")
                )
            }
        }
    }

    private func ensureSelection() {
        guard let store = selectedStore else {
            selectedScriptID = nil
            return
        }

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

private struct BottleMacroRow: View {
    @ObservedObject var bottle: Bottle
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(isActive ? .green : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(bottle.settings.name)
                    .lineLimit(1)
                Text(bottle.settings.gamePreset.rawValue.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Text("前台")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MacroListView: View {
    @ObservedObject var store: BottleMacroStore
    @Binding var selection: UUID?
    let onAddTrigger: (UUID) -> Void

    @State private var renameTarget: MacroScript?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("按键宏")
                        .font(.headline)
                    Text("\(store.settings.scripts.count) 个宏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    let id = store.addScript()
                    selection = id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建宏")
            }
            .padding(14)

            List(selection: $selection) {
                ForEach(store.settings.scripts) { script in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(script.displayName)
                            .lineLimit(1)
                        if script.bindings.isEmpty {
                            Text("未绑定触发键")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(script.bindings.map(\.trigger.displayName).joined(separator: "  "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(script.id)
                    .contextMenu {
                        Button("重命名") {
                            renameTarget = script
                            renameText = script.displayName
                        }
                        Button("添加触发键") {
                            selection = script.id
                            onAddTrigger(script.id)
                        }
                        Divider()
                        Button("复制") {
                            selection = store.duplicateScript(id: script.id)
                        }
                        Button("删除", role: .destructive) {
                            store.deleteScript(id: script.id)
                            if selection == script.id {
                                selection = store.settings.scripts.first?.id
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Toggle("此容器启用宏", isOn: Binding(
                    get: { store.settings.enabled },
                    set: { store.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .font(.caption)
                Spacer()
                if let saved = store.lastSavedAt {
                    Text("已保存 \(saved.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .alert("重命名宏", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("确定") {
                if let renameTarget {
                    store.renameScript(id: renameTarget.id, name: renameText)
                }
                renameTarget = nil
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
                ContentUnavailableView("宏不存在", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func header(script: MacroScript) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                TextField("宏名称", text: nameBinding)
                    .font(.title3)
                    .textFieldStyle(.plain)
                Spacer()
                Button {
                    store.saveNow()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                Button {
                    service.test(script: script, store: store)
                } label: {
                    Label("测试", systemImage: "play.fill")
                }
                .disabled(service.activeTargetPID == 0)
                .help("让游戏位于前台后测试宏")
            }

            HStack(spacing: 8) {
                Label(service.macroStatus.label, systemImage: service.macroRunning ? "waveform" : "pause.circle")
                    .font(.caption)
                    .foregroundStyle(service.macroRunning ? .blue : .secondary)
                if service.macroRunning {
                    Button("停止") {
                        service.stopMacro()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                Spacer()
                Text(script.summary)
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
                        Text("例如：{WAITMS:100}s{WAITMS:100}{LMB}")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }

            parseStatus

            HStack(spacing: 8) {
                Text("默认按住")
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
                "解析成功：\(items.count) 个动作，\(MacroDSL.durationText(of: items))",
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("触发键")
                        .font(.headline)
                    Text("原始触发键默认仍会传给游戏；发生冲突时由游戏内按键设置处理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    onCaptureTrigger()
                } label: {
                    Label("录制触发键", systemImage: "record.circle")
                }
            }

            if script.bindings.isEmpty {
                Text("还没有触发键。点击“录制触发键”，然后按下键盘按键或鼠标侧键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(script.bindings) { binding in
                    TriggerBindingRow(
                        store: store,
                        scriptID: script.id,
                        binding: binding
                    )
                }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(binding.trigger.displayName)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                Picker("模式", selection: Binding(
                    get: { binding.mode },
                    set: { store.updateBinding(scriptID: scriptID, bindingID: binding.id, mode: $0) }
                )) {
                    ForEach(MacroTriggerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 230)

                Spacer()

                Toggle("启用", isOn: Binding(
                    get: { binding.enabled },
                    set: { store.updateBinding(scriptID: scriptID, bindingID: binding.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .font(.caption)

                Button(role: .destructive) {
                    store.removeBinding(scriptID: scriptID, bindingID: binding.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            Text(binding.mode.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("阻止 macOS 系统快捷键（实验性）", isOn: Binding(
                get: { binding.preventSystemShortcut },
                set: { store.updateBinding(scriptID: scriptID, bindingID: binding.id, preventSystemShortcut: $0) }
            ))
            .toggleStyle(.switch)
            .font(.caption)

            Text(
                "开启后会先拦截 macOS 的系统快捷键，再把原始按键转发给当前游戏。"
                    + "若宏里也写了同一个键，可能造成重复输入。"
            )
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
    @State private var message = "正在等待按键…"

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 38))
                .foregroundStyle(.blue)
            Text("录制触发键")
                .font(.title2)
            Text(message)
                .foregroundStyle(.secondary)
            Text("按下任意键盘按键、组合键或鼠标侧键（4/5）。单独按修饰键不会被记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack {
                Button("取消") {
                    service.cancelCapture()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 430, height: 260)
        .onAppear {
            guard !started else { return }
            started = true
            let began = service.beginCapture { trigger in
                onCapture(trigger)
                dismiss()
            }
            if !began {
                message = service.lastError ?? "无法开始录制。"
            }
        }
        .onDisappear {
            service.cancelCapture()
        }
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
