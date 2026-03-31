import SwiftUI
import WhiskyKit

struct WineRuntimesSetupView: View {
    @StateObject private var vm = WineRuntimeDownloadsVM()
    @Binding var showSetup: Bool
    @State private var availableRuntimes: [WineRuntime] = WineRuntimes.all

    private var isSetupReady: Bool {
        WineRuntimes.all.contains { runtime in
            runtime.id != WineRuntimes.whiskyDefaultId
                && runtime.renderBackend == .dxmt
                && vm.isInstalled(runtime.id)
        }
    }

    var body: some View {
        VStack {
            VStack {
                Text("runtime.setup.title")
                    .font(.title)
                    .fontWeight(.bold)
                Text("runtime.setup.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            Form {
                ForEach(availableRuntimes, id: \.id) { runtime in
                    let state = vm.items[runtime.id] ?? WineRuntimeDownloadsVM.ItemState()
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(runtime.displayName)
                            Text(vm.isInstalled(runtime.id) ? String(localized: "runtime.status.installed") : String(localized: "runtime.status.notInstalled"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()

                        if vm.isInstalled(runtime.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.medium)
                        } else if state.isBusy {
                            Button {
                                vm.cancel(runtimeId: runtime.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.medium)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "button.cancel"))
                        } else {
                            Button("runtime.setup.download") {
                                vm.download(runtimeId: runtime.id)
                            }
                        }
                    }

                    if state.isBusy {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(state.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let p = state.progress {
                                ProgressView(value: p)
                            } else {
                                ProgressView()
                            }
                        }
                    } else if let error = state.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Spacer()

            HStack {
                Button("setup.done") {
                    showSetup = false
                }
                .disabled(!isSetupReady)
            }
        }
        .frame(width: 520, height: 430)
        .task {
            availableRuntimes = await WineRuntimes.refreshCatalog(forceRemote: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: WineRuntimes.didUpdateNotification)) { _ in
            availableRuntimes = WineRuntimes.all
        }
    }
}
