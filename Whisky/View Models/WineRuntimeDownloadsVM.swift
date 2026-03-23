import Foundation
import WhiskyKit

@MainActor
final class WineRuntimeDownloadsVM: ObservableObject {
    struct ItemState {
        var selected: Bool = false
        var isBusy: Bool = false
        var status: String = ""
        var progress: Double? = nil
        var errorMessage: String? = nil
    }

    @Published var items: [String: ItemState] = [:]

    init() {
        for runtime in WineRuntimes.all {
            var state = ItemState()
            if runtime.id == "11.0-dxmt-signed" {
                state.selected = true
            }
            items[runtime.id] = state
        }
    }

    func isInstalled(_ runtimeId: String) -> Bool {
        WineRuntimeManager.isInstalled(runtimeId: runtimeId)
    }

    func toggleSelected(_ runtimeId: String) {
        items[runtimeId, default: ItemState()].selected.toggle()
    }

    func download(runtimeId: String) {
        guard !items[runtimeId, default: ItemState()].isBusy else { return }

        items[runtimeId, default: ItemState()].isBusy = true
        items[runtimeId, default: ItemState()].errorMessage = nil
        items[runtimeId, default: ItemState()].status = "Starting"
        items[runtimeId, default: ItemState()].progress = nil

        Task.detached(priority: .userInitiated) {
            do {
                try await WineRuntimeManager.ensureInstalled(
                    runtimeId: runtimeId,
                    status: { message in
                        Task { @MainActor in
                            self.items[runtimeId, default: ItemState()].status = message
                        }
                    },
                    progress: { frac in
                        Task { @MainActor in
                            self.items[runtimeId, default: ItemState()].progress = frac
                        }
                    }
                )
                await MainActor.run {
                    self.items[runtimeId, default: ItemState()].status = "Installed"
                    self.items[runtimeId, default: ItemState()].progress = 1
                    self.items[runtimeId, default: ItemState()].isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.items[runtimeId, default: ItemState()].status = "Failed"
                    self.items[runtimeId, default: ItemState()].progress = nil
                    self.items[runtimeId, default: ItemState()].errorMessage = error.localizedDescription
                    self.items[runtimeId, default: ItemState()].isBusy = false
                }
            }
        }
    }

    func downloadSelected() {
        Task.detached(priority: .userInitiated) {
            let ids = await MainActor.run {
                WineRuntimes.all.map(\.id).filter { self.items[$0]?.selected == true }
            }
            for id in ids {
                let skip = await MainActor.run { self.isInstalled(id) || (self.items[id]?.isBusy == true) }
                if skip {
                    continue
                }

                await MainActor.run {
                    self.download(runtimeId: id)
                }

                // Wait until the current download finishes before moving to next.
                while await MainActor.run { self.items[id]?.isBusy == true } {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
    }
}
