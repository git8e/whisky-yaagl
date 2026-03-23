import Foundation
import WhiskyKit

@MainActor
final class WineRuntimeDownloadsVM: ObservableObject {
    struct ItemState {
        var isBusy: Bool = false
        var status: String = ""
        var progress: Double? = nil
        var errorMessage: String? = nil
    }

    @Published var items: [String: ItemState] = [:]

    init() {
        for runtime in WineRuntimes.all {
            var state = ItemState()
            items[runtime.id] = state
        }
    }

    func isInstalled(_ runtimeId: String) -> Bool {
        WineRuntimeManager.isInstalled(runtimeId: runtimeId)
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

}
