import AppKit
import SwiftUI
import WhiskyKit

struct HoYoPlayInstallPinView: View {
    @ObservedObject var bottle: Bottle
    let info: HoYoPlayContent

    @State private var isWorking = false
    @State private var progress: Double?

    var body: some View {
        Button {
            installHoYoPlay()
        } label: {
            VStack {
                Color.clear
                    .frame(height: 8)
                ZStack(alignment: .topTrailing) {
                    Image("HoYoPlayIcon")
                        .resizable()
                    .frame(width: 45, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    if isWorking {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.black.opacity(0.18))
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial.opacity(0.78))
                            ProgressView(value: progress)
                                .controlSize(.small)
                                .frame(width: 26)
                        }
                        .frame(width: 46, height: 46)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .foregroundColor(.accentColor)
                            .frame(width: 16, height: 16)
                            .padding(.top, 2)
                            .padding(.trailing, 2)
                    }
                }
                .frame(width: 45, height: 45)
                Spacer()
                Text(info.displayName)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(info.displayName)
            }
            .frame(width: 90, height: 90)
            .padding(10)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .contextMenu {
            Button("hoyoplay.openWebsite", systemImage: "safari") {
                openManualDownloadPage()
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private func installHoYoPlay() {
        guard !isWorking else { return }

        Task(priority: .userInitiated) {
            let latestInfo = await LauncherContent.refresh(forceRemote: true) ?? info

            await MainActor.run {
                isWorking = true
                progress = 0
            }

            do {
                guard let installerURL = latestInfo.installerURL else {
                    throw HoYoPlayInstallError.missingInstallerURL
                }

                let localInstallerURL = try installerDestination(for: installerURL)
                defer {
                    try? FileManager.default.removeItem(at: localInstallerURL)
                }

                do {
                    try await RemoteDownloader.downloadOnce(
                        url: installerURL,
                        destination: localInstallerURL,
                        progress: { fraction in
                            Task { @MainActor in
                                progress = fraction
                            }
                        }
                    )
                } catch {
                    guard let fallbackURL = latestInfo.fallbackInstallerURL else {
                        throw error
                    }

                    try await RemoteDownloader.downloadOnce(
                        url: fallbackURL,
                        destination: localInstallerURL,
                        progress: { fraction in
                            Task { @MainActor in
                                progress = fraction
                            }
                        }
                    )
                }

                await MainActor.run {
                    progress = nil
                }

                _ = try await Wine.runWine(
                    ["start", "/wait", "/unix", localInstallerURL.path(percentEncoded: false)],
                    bottle: bottle
                )

                await MainActor.run {
                    bottle.refreshProgramsAndPinsFromDisk()
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    progress = nil
                    showManualInstallAlert(info: latestInfo, reason: error.localizedDescription)
                }
            }
        }
    }

    private func installerDestination(for remoteURL: URL) throws -> URL {
        let folder = WhiskyWineInstaller.applicationFolder
            .appending(path: "Downloads", directoryHint: .isDirectory)
            .appending(path: "Installers", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appending(path: remoteURL.lastPathComponent, directoryHint: .notDirectory)
    }

    @MainActor
    private func showManualInstallAlert(info: HoYoPlayContent, reason: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "hoyoplay.install.failed.title")
        alert.informativeText = String(
            format: String(localized: "hoyoplay.install.failed.message"),
            reason
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "hoyoplay.openWebsite"))
        alert.addButton(withTitle: String(localized: "button.ok"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openManualDownloadPage(info: info)
        }
    }

    private func openManualDownloadPage(info: HoYoPlayContent? = nil) {
        let resolvedInfo = info ?? self.info
        guard let url = resolvedInfo.manualDownloadURL else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum HoYoPlayInstallError: LocalizedError {
    case missingInstallerURL

    var errorDescription: String? {
        switch self {
        case .missingInstallerURL:
            return String(localized: "hoyoplay.error.missingInstallerURL")
        }
    }
}
