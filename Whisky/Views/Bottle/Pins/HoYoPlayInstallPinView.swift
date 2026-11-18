import AppKit
import SwiftUI
import WhiskyKit

struct HoYoPlayInstallPinView: View {
    @ObservedObject var bottle: Bottle
    let info: HoYoPlayContent
    let onInstallFinished: () -> Void

    @State private var isWorking = false
    @State private var progress: Double?
    @State private var isRevealing = false
    @State private var didFinishInstall = false
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
            VStack(spacing: PinLayout.iconLabelSpacing) {
                ZStack {
                    Image("HoYoPlayIcon")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.primary)
                        .frame(width: PinLayout.iconContentSize, height: PinLayout.iconContentSize)

                    if isWorking {
                        IOSInstallOverlay(progress: progress, isRevealing: isRevealing)
                            .frame(width: PinLayout.iconContentSize, height: PinLayout.iconContentSize)
                    }
                }
                .frame(width: PinLayout.iconSize, height: PinLayout.iconSize)
                .overlay(alignment: .topTrailing) {
                    if !isWorking && !didFinishInstall {
                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .foregroundColor(.accentColor)
                            .frame(width: 20, height: 20)
                            .padding(.top, 2)
                            .padding(.trailing, 2)
                    }
                }
                Text(info.displayName)
                    .font(PinLayout.labelFont)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: PinLayout.labelWidth)
                    .help(info.displayName)
            }
            .frame(width: PinLayout.cellWidth, height: PinLayout.cellHeight, alignment: .top)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isWorking)
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
                isRevealing = false
                didFinishInstall = false
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
                    progress = 1
                }

                // `wine start` does not necessarily activate the installer's
                // Qt window. Run the installer in the background while we wait
                // for its window, then bring it forward so the Install button
                // receives the first click.
                let windowSnapshot = WineWindowSnapshot.capture()
                let installTask = Task {
                    try await Wine.runWine(
                        ["start", "/wait", "/unix", localInstallerURL.path(percentEncoded: false)],
                        bottle: bottle,
                        environment: HoYoPlayLaunch.installerEnvironment
                    )
                }

                let installerWindowAppeared = await HoYoPlayLaunch.activateNewWindow(
                    since: windowSnapshot,
                    timeout: 30
                )

                // The original iOS-style reveal starts as soon as the app's
                // window appears, not when the installation finishes. The
                // installer can stay open while the pin has already revealed
                // the normal HoYoPlay icon.
                if installerWindowAppeared {
                    await MainActor.run {
                        isRevealing = true
                    }
                }

                _ = try await installTask.value

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
                    didFinishInstall = true
                    if installerWindowAppeared {
                        onInstallFinished()
                        isWorking = false
                        isRevealing = false
                    } else {
                        // Fallback for an installer whose window could not be
                        // detected: still play the completion reveal once.
                        isRevealing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                            onInstallFinished()
                            isWorking = false
                            isRevealing = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    progress = nil
                    isRevealing = false
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

private struct IOSInstallOverlay: View {
    let progress: Double?
    let isRevealing: Bool

    @State private var startupProgress: Double = 0
    @State private var ringScale: Double = 0.16
    @State private var reveal: Double = 0

    private var targetProgress: Double {
        min(max(progress ?? 0, 0), 1)
    }

    private var displayProgress: Double {
        max(targetProgress, startupProgress)
    }

    private var trackOuter: Double {
        0.75 * ringScale
    }

    private var trackWidth: Double {
        0.11
    }

    private var ringWidth: Double {
        trackWidth * ringScale
    }

    private var cutoutOuter: Double {
        trackOuter + reveal * 2.0
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.46))

            // The transparent sector grows through the mask like the iOS
            // install indicator. The centre is deliberately left open so the
            // icon shows through; a solid centre only belongs to the paused
            // state in the original animation.
            RingSector(
                progress: displayProgress,
                innerRatio: 0,
                outerRatio: cutoutOuter
            )
            .fill(.white, style: FillStyle(eoFill: true))
            .animation(.linear(duration: 0.22), value: targetProgress)
            .blendMode(.destinationOut)

            // The ring is a transparent cutout in the mask, not a painted
            // stroke. It reveals the icon's own appearance and spans three
            // quarters of the app icon.
            RingSector(
                progress: 1,
                innerRatio: max(0, trackOuter - ringWidth),
                outerRatio: trackOuter
            )
            .fill(.white, style: FillStyle(eoFill: true))
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            startInstallAnimation()
        }
        .onChange(of: isRevealing) { _, revealing in
            guard revealing else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                reveal = 1
            }
        }
    }

    private func startInstallAnimation() {
        startupProgress = 0
        ringScale = 0.16
        reveal = 0

        // The ring appears first, growing from the centre like the iOS
        // install indicator, then the first sector starts sweeping.
        withAnimation(.easeOut(duration: 0.35)) {
            ringScale = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.42)) {
                startupProgress = 30.0 / 360.0
            }
        }
    }
}

private struct RingSector: Shape {
    var progress: Double
    var innerRatio: Double
    var outerRatio: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get {
            AnimatablePair(progress, AnimatablePair(innerRatio, outerRatio))
        }
        set {
            progress = newValue.first
            innerRatio = newValue.second.first
            outerRatio = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfSize = min(rect.width, rect.height) / 2
        let inner = max(0, min(innerRatio, outerRatio)) * halfSize
        let outer = max(0, max(innerRatio, outerRatio)) * halfSize
        let sweep = 360 * min(max(progress, 0), 1)

        guard outer > 0.001, sweep > 0.001 else { return Path() }

        var path = Path()

        if sweep >= 359.999 {
            path.addEllipse(in: CGRect(
                x: center.x - outer,
                y: center.y - outer,
                width: outer * 2,
                height: outer * 2
            ))

            if inner > 0.001 {
                path.addEllipse(in: CGRect(
                    x: center.x - inner,
                    y: center.y - inner,
                    width: inner * 2,
                    height: inner * 2
                ))
            }

            return path
        }

        let start = Angle.degrees(-90)
        let end = Angle.degrees(-90 + sweep)

        path.addArc(
            center: center,
            radius: outer,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )

        if inner > 0.001 {
            path.addArc(
                center: center,
                radius: inner,
                startAngle: end,
                endAngle: start,
                clockwise: true
            )
        } else {
            path.addLine(to: center)
        }

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
