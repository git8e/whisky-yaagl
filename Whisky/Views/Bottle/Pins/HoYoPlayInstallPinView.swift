import AppKit
import SwiftUI
import WhiskyKit

struct HoYoPlayInstallPinView: View {
    @ObservedObject var bottle: Bottle
    let info: HoYoPlayContent
    let onInstallFinished: () -> Void

    @State private var isWorking = false
    @State private var progress: Double?
    @State private var showInstallNotice = false

    init(bottle: Bottle, info: HoYoPlayContent, onInstallFinished: @escaping () -> Void = {}) {
        self.bottle = bottle
        self.info = info
        self.onInstallFinished = onInstallFinished
    }

    var body: some View {
        Button {
            guard !isWorking else { return }
            showInstallNotice = true
        } label: {
            VStack {
                Color.clear
                    .frame(height: 8)
                ZStack(alignment: .topTrailing) {
                    Image("HoYoPlayIcon")
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(.primary)
                        .frame(width: 45, height: 45)

                    if isWorking {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(0.42))
                            Circle()
                                .strokeBorder(.white.opacity(0.30), lineWidth: 0.75)
                            AppleStyleProgressRing(progress: progress)
                                .frame(width: 32, height: 32)
                        }
                        .frame(width: 46, height: 46)
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
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
        .alert(
            String(localized: "hoyoplay.install.notice.title"),
            isPresented: $showInstallNotice
        ) {
            Button(String(localized: "button.cancel"), role: .cancel) { }
            Button(String(localized: "hoyoplay.install.notice.continue")) {
                installHoYoPlay()
            }
        } message: {
            Text(String(localized: "hoyoplay.install.notice.message"))
        }
    }

    @MainActor
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

                // `wine start` does not necessarily activate the installer's
                // Qt window. Bring it forward once it appears so the Install
                // button receives the first click.
                let windowSnapshot = WineWindowSnapshot.capture()
                let activationTask = Task {
                    _ = await HoYoPlayLaunch.activateNewWindow(
                        since: windowSnapshot,
                        timeout: 30
                    )
                }
                defer { activationTask.cancel() }

                _ = try await Wine.runWine(
                    ["start", "/wait", "/unix", localInstallerURL.path(percentEncoded: false)],
                    bottle: bottle,
                    environment: HoYoPlayLaunch.installerEnvironment
                )

                // Under DXMT the installer finishes by starting a headless
                // `HYP.exe --jump=installer` that holds the launcher singleton
                // and blocks later launches, so get rid of it first.
                let relaunchLauncher = HoYoPlayLaunch.terminateInstallerLaunchedProcesses()

                await waitForInstallRefresh(info: latestInfo)

                // Honour the installer's "launch HoYoPlay" option, but start
                // the launcher through the same path the pin uses.
                if relaunchLauncher, let launcherURL = launcherURL(for: latestInfo) {
                    try? await Wine.runProgram(at: launcherURL, bottle: bottle)
                }

                await MainActor.run {
                    onInstallFinished()
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

    private func waitForInstallRefresh(info: HoYoPlayContent) async {
        for attempt in 0..<20 {
            let installed = await MainActor.run {
                bottle.refreshProgramsAndPinsFromDisk()
                return info.isInstalled(in: bottle)
            }
            if installed || attempt == 19 {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func launcherURL(for info: HoYoPlayContent) -> URL? {
        for path in info.detectionPaths {
            let url = bottle.url
                .appending(path: path, directoryHint: .isDirectory)
                .appending(path: "launcher.exe", directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return url
            }
        }
        return nil
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

private struct AppleStyleProgressRing: View {
    let progress: Double?

    @State private var startupFraction: Double = 0
    @State private var pulse = false

    private var targetFraction: Double {
        min(max(progress ?? 0, 0), 1)
    }

    private var displayFraction: Double {
        max(targetFraction, startupFraction)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2

            ZStack {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)

                Circle()
                    .strokeBorder(.black.opacity(0.12), lineWidth: 0.75)

                ProgressSector(progress: displayFraction)
                    .fill(Color.blue)
                    .animation(.linear(duration: 0.22), value: targetFraction)

                if targetFraction < 0.995 {
                    Circle()
                        .fill(.white)
                        .frame(width: 3.2, height: 3.2)
                        .offset(y: -(radius - 2.8))
                        .rotationEffect(.degrees(360 * displayFraction))
                        .opacity(pulse ? 0.95 : 0.30)
                        .shadow(color: .black.opacity(0.40), radius: 1)
                        .animation(
                            .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                            value: pulse
                        )
                }
            }
        }
        .onAppear {
            startStartupSweep()
        }
        .onChange(of: progress) { _, newValue in
            if newValue == nil || (newValue ?? 0) <= 0.001 {
                startStartupSweep()
            }
        }
    }

    private func startStartupSweep() {
        startupFraction = 0
        pulse = false

        // Give immediate feedback as soon as the install starts. The first
        // 30° fills quickly, then holds until real download progress arrives.
        withAnimation(.easeOut(duration: 0.42)) {
            startupFraction = 30.0 / 360.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ProgressSector: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let sweep = 360 * min(max(progress, 0), 1)

        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + sweep),
            clockwise: false
        )
        path.closeSubpath()
        return path
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
