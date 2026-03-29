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

    func isInstalled(_ runtimeId: String) -> Bool {
        WineRuntimeManager.isInstalled(runtimeId: runtimeId)
    }

    func download(runtimeId: String) {
        guard !items[runtimeId, default: ItemState()].isBusy else { return }

        items[runtimeId, default: ItemState()].isBusy = true
        items[runtimeId, default: ItemState()].errorMessage = nil
        items[runtimeId, default: ItemState()].status = localizedRuntimeStatus("Starting")
        items[runtimeId, default: ItemState()].progress = nil

        Task.detached(priority: .userInitiated) {
            do {
                try await WineRuntimeManager.ensureInstalled(
                    runtimeId: runtimeId,
                    status: { message in
                        Task { @MainActor in
                            self.items[runtimeId, default: ItemState()].status = self.localizedRuntimeStatus(message)
                        }
                    },
                    progress: { frac in
                        Task { @MainActor in
                            self.items[runtimeId, default: ItemState()].progress = frac
                        }
                    }
                )
                await MainActor.run {
                    self.items[runtimeId, default: ItemState()].status = self.localizedRuntimeStatus("Installed")
                    self.items[runtimeId, default: ItemState()].progress = 1
                    self.items[runtimeId, default: ItemState()].isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.items[runtimeId, default: ItemState()].status = self.localizedRuntimeStatus("Failed")
                    self.items[runtimeId, default: ItemState()].progress = nil
                    self.items[runtimeId, default: ItemState()].errorMessage = error.localizedDescription
                    self.items[runtimeId, default: ItemState()].isBusy = false
                }
            }
        }
    }

    private func localizedRuntimeStatus(_ status: String) -> String {
        switch status {
        case "Starting":
            return String(localized: "runtime.status.starting")
        case "Installed":
            return String(localized: "runtime.status.installed")
        case "Not Installed":
            return String(localized: "runtime.status.notInstalled")
        case "Failed":
            return String(localized: "runtime.status.failed")
        case "Downloading WhiskyWine":
            return String(localized: "runtime.status.downloadingWhiskyWine")
        case "Installing WhiskyWine":
            return String(localized: "runtime.status.installingWhiskyWine")
        case "Downloading Wine runtime":
            return String(localized: "runtime.status.downloadingWineRuntime")
        case "Installing Wine runtime":
            return String(localized: "runtime.status.installingWineRuntime")
        case "Installing Wine from local archive":
            return String(localized: "runtime.status.installingWineFromArchive")
        case "Preparing isolated Wine runtime":
            return String(localized: "runtime.status.preparingIsolatedRuntime")
        default:
            return status
        }
    }

}
