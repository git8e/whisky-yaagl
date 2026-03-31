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

    private var tasks: [String: Task<Void, Never>] = [:]

    func isInstalled(_ runtimeId: String) -> Bool {
        WineRuntimeManager.isInstalled(runtimeId: runtimeId)
    }

    func download(runtimeId: String) {
        guard !items[runtimeId, default: ItemState()].isBusy else { return }

        tasks[runtimeId]?.cancel()
        tasks[runtimeId] = nil

        items[runtimeId, default: ItemState()].isBusy = true
        items[runtimeId, default: ItemState()].errorMessage = nil
        items[runtimeId, default: ItemState()].status = localizedRuntimeStatus("Starting")
        items[runtimeId, default: ItemState()].progress = nil

        let task = Task(priority: .userInitiated) {
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
                try Task.checkCancellation()
                self.items[runtimeId, default: ItemState()].status = self.localizedRuntimeStatus("Installed")
                self.items[runtimeId, default: ItemState()].progress = 1
                self.items[runtimeId, default: ItemState()].isBusy = false
                self.tasks[runtimeId] = nil
            } catch is CancellationError {
                self.items[runtimeId, default: ItemState()].status = self.localizedRuntimeStatus("Cancelled")
                self.items[runtimeId, default: ItemState()].progress = nil
                self.items[runtimeId, default: ItemState()].errorMessage = nil
                self.items[runtimeId, default: ItemState()].isBusy = false
                self.tasks[runtimeId] = nil
            } catch {
                self.items[runtimeId, default: ItemState()].status = self.localizedRuntimeStatus("Failed")
                self.items[runtimeId, default: ItemState()].progress = nil
                self.items[runtimeId, default: ItemState()].errorMessage = userFacingErrorMessage(error)
                self.items[runtimeId, default: ItemState()].isBusy = false
                self.tasks[runtimeId] = nil
            }
        }
        tasks[runtimeId] = task
    }

    func cancel(runtimeId: String) {
        tasks[runtimeId]?.cancel()
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
        case "Cancelled":
            return String(localized: "runtime.status.cancelled")
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

    private func userFacingErrorMessage(_ error: Error) -> String {
        if let error = error as? WineRuntimeManagerError {
            return error.localizedDescription
        }

        if let error = error as? RemoteDownloader.DownloadError {
            return error.userFacingDescription
        }

        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet:
                return String(localized: "runtime.error.noInternet")
            case .timedOut:
                return String(localized: "runtime.error.timedOut")
            case .cannotFindHost, .dnsLookupFailed:
                return String(localized: "runtime.error.dns")
            case .cannotConnectToHost, .networkConnectionLost:
                return String(localized: "runtime.error.network")
            case .cancelled:
                return String(localized: "runtime.error.cancelled")
            default:
                break
            }
        }

        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return String(localized: "runtime.error.noSpace")
        }

        return String(localized: "runtime.error.generic")
    }

}
