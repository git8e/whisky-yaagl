import SwiftUI
import WhiskyKit

struct WineRuntimesSetupView: View {
    @StateObject private var vm = WineRuntimeDownloadsVM()
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            VStack {
                Text("Wine Runtimes")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Select any runtimes to download. Wine 11.0 DXMT is recommended.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            Form {
                ForEach(WineRuntimes.all, id: \.id) { runtime in
                    let state = vm.items[runtime.id] ?? WineRuntimeDownloadsVM.ItemState()
                    HStack {
                        Toggle(isOn: Binding(
                            get: { vm.items[runtime.id]?.selected ?? false },
                            set: { _ in vm.toggleSelected(runtime.id) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(runtime.displayName)
                                Text(vm.isInstalled(runtime.id) ? "Installed" : "Not Installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button(vm.isInstalled(runtime.id) ? "Downloaded" : "Download") {
                            vm.download(runtimeId: runtime.id)
                        }
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
            .scrollDisabled(true)

            Spacer()

            HStack {
                Button("Download Selected") {
                    vm.downloadSelected()
                }
                .keyboardShortcut(.defaultAction)

                Spacer()

                Button("Done") {
                    showSetup = false
                }
                .disabled(!vm.isInstalled("11.0-dxmt-signed"))
            }
        }
        .frame(width: 520, height: 420)
    }
}
