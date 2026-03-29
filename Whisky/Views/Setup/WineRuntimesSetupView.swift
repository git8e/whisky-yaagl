import SwiftUI
import WhiskyKit

struct WineRuntimesSetupView: View {
    @StateObject private var vm = WineRuntimeDownloadsVM()
    @Binding var showSetup: Bool
    @State private var availableRuntimes: [WineRuntime] = WineRuntimes.all

    private var preferredRuntimeId: String? {
        WineRuntimes.preferredSetupRuntime?.id
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
                        Toggle(
                            "runtime.setup.download",
                            isOn: Binding(
                                get: { vm.isInstalled(runtime.id) || state.isBusy },
                                set: { newValue in
                                    if newValue {
                                        vm.download(runtimeId: runtime.id)
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .disabled(vm.isInstalled(runtime.id) || state.isBusy)
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
                .disabled(preferredRuntimeId.map { !vm.isInstalled($0) } ?? false)
            }
        }
        .frame(width: 520, height: 520)
        .task {
            availableRuntimes = await WineRuntimes.refreshCatalog(forceRemote: false)
            if let runtimeId = preferredRuntimeId, !vm.isInstalled(runtimeId) {
                vm.download(runtimeId: runtimeId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WineRuntimes.didUpdateNotification)) { _ in
            availableRuntimes = WineRuntimes.all
        }
    }
}
