//
//  HK4eProtonExtras.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

public enum HK4eProtonExtras {
    private static var fm: FileManager { FileManager.default }

    // Prefer downloading only the required files directly from the YAAGL repository.
    // This avoids downloading the whole app sidecar tarball.
    private static let rawBaseURL = URL(
        string: "https://raw.githubusercontent.com/yaagl/yet-another-anime-game-launcher/main/sidecar/protonextras/"
    )!

    // Fallback: download YAAGL app tarball and extract protonextras.
    private static let owner = "yaagl"
    private static let repo = "yet-another-anime-game-launcher"

    public static var protonExtrasDir: URL {
        WhiskyWineInstaller.libraryFolder
            .appending(path: "HK4e", directoryHint: .isDirectory)
            .appending(path: "protonextras", directoryHint: .isDirectory)
    }

    private static let requiredFiles = [
        "steam64.exe",
        "steam32.exe",
        "lsteamclient64.dll",
        "lsteamclient32.dll"
    ]

    public static func isInstalled() -> Bool {
        return requiredFiles.allSatisfy { name in
            let url = protonExtrasDir.appending(path: name)
            return fm.fileExists(atPath: url.path(percentEncoded: false))
        }
    }

    public static func ensureInstalled(
        status: (@Sendable (String) -> Void)? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if isInstalled() {
            return
        }

        do {
            try await downloadRawProtonExtras(status: status, progress: progress)
        } catch {
            // Fall back to YAAGL sidecar extraction if raw download is unavailable.
            status?("Fetching YAAGL sidecar")
            let sidecarURL = try await latestSidecarURL()
            let archive = try await downloadOnce(url: sidecarURL, status: status, progress: progress)
            status?("Extracting protonextras")
            try extractProtonExtras(from: archive)
        }

        removeQuarantineRecursively(path: protonExtrasDir.path(percentEncoded: false))

        guard isInstalled() else {
            throw HK4eProtonExtrasError.installFailed
        }
    }

    private static func downloadRawProtonExtras(
        status: (@Sendable (String) -> Void)?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        let destDir = protonExtrasDir
        if !fm.fileExists(atPath: destDir.path(percentEncoded: false)) {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        let urls = requiredFiles.map { name in
            (name, rawBaseURL.appending(path: name))
        }

        // Best-effort total size for overall progress.
        var sizes: [String: Int64] = [:]
        for (name, url) in urls {
            if let size = try? await contentLength(url: url) {
                sizes[name] = size
            }
        }
        let totalSize = sizes.values.reduce(0, +)

        let count = max(urls.count, 1)
        var completedBytes: Int64 = 0
        for (index, pair) in urls.enumerated() {
            let name = pair.0
            let url = pair.1
            let dst = destDir.appending(path: name)
            if fm.fileExists(atPath: dst.path(percentEncoded: false)) {
                if let s = sizes[name] {
                    completedBytes += s
                }
                continue
            }

            status?("Downloading protonextras: \(name)")
            let fileSize = sizes[name]
            let startingCompletedBytes = completedBytes
            let base = Double(index) / Double(count)
            let step = 1.0 / Double(count)

            var perFileProgress: (@Sendable (Double) -> Void)?
            if let progressCb = progress {
                perFileProgress = { frac in
                    let clampedFrac = min(max(frac, 0.0), 1.0)
                    if totalSize > 0, let fileSize {
                        let overall = Double(startingCompletedBytes) / Double(totalSize)
                            + (Double(fileSize) / Double(totalSize)) * clampedFrac
                        progressCb(min(max(overall, 0.0), 1.0))
                    } else {
                        progressCb(min(max(base + step * clampedFrac, 0.0), 1.0))
                    }
                }
            }

            _ = try await downloadFile(url: url, to: dst, progress: perFileProgress)

            if let fileSize {
                completedBytes += fileSize
            }
        }
    }

    private static func contentLength(url: URL) async throws -> Int64 {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        let (_, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        guard let http = resp as? HTTPURLResponse,
              let value = http.value(forHTTPHeaderField: "Content-Length"),
              let size = Int64(value) else {
            throw HK4eProtonExtrasError.missingContentLength
        }
        return size
    }

    private static func downloadFile(
        url: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }

        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let task = session.downloadTask(with: url)
        return try await withCheckedThrowingContinuation { cont in
            delegate.continuation = cont
            task.resume()
        }
    }

    private static func latestSidecarURL() async throws -> URL {
        let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("whisky-yaagl", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: req)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        let preferredNames = [
            "Yaagl.OS.app.tar.gz",
            "Yaagl.app.tar.gz"
        ]

        for name in preferredNames {
            if let asset = release.assets.first(where: { $0.name == name }),
               let url = URL(string: asset.browser_download_url) {
                return url
            }
        }

        if let asset = release.assets.first(where: { $0.name.hasSuffix(".app.tar.gz") }),
           let url = URL(string: asset.browser_download_url) {
            return url
        }

        throw HK4eProtonExtrasError.noSidecarAsset
    }

    private static func downloadOnce(
        url: URL,
        status: (@Sendable (String) -> Void)?,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let downloads = try downloadsFolder()
        let destination = downloads.appending(path: "yaagl-sidecar-\(url.lastPathComponent)")

        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }

        status?("Downloading sidecar archive")
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let task = session.downloadTask(with: url)
        return try await withCheckedThrowingContinuation { cont in
            delegate.continuation = cont
            task.resume()
        }
    }

    private static func downloadsFolder() throws -> URL {
        let url = WhiskyWineInstaller.applicationFolder.appending(path: "Downloads", directoryHint: .isDirectory)
        if !fm.fileExists(atPath: url.path(percentEncoded: false)) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static func extractProtonExtras(from archiveURL: URL) throws {
        let dest = protonExtrasDir
        if !fm.fileExists(atPath: dest.path(percentEncoded: false)) {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        }

        // Extract only `*/Contents/Resources/sidecar/protonextras/*` from the app tarball.
        try Tar.extract(
            tarBall: archiveURL,
            toURL: dest,
            paths: ["*/Contents/Resources/sidecar/protonextras/*"],
            stripComponents: 5,
            useWildcards: true
        )
    }

    private static func removeQuarantineRecursively(path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-dr", "com.apple.quarantine", path]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            // best-effort
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let destination: URL
        let progress: (@Sendable (Double) -> Void)?
        var continuation: CheckedContinuation<URL, Error>?

        init(destination: URL, progress: (@Sendable (Double) -> Void)?) {
            self.destination = destination
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let frac = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progress?(min(max(frac, 0.0), 1.0))
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            do {
                if HK4eProtonExtras.fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                    continuation?.resume(returning: destination)
                    continuation = nil
                    return
                }
                try HK4eProtonExtras.fm.moveItem(at: location, to: destination)
                continuation?.resume(returning: destination)
                continuation = nil
            } catch {
                continuation?.resume(throwing: error)
                continuation = nil
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private struct GitHubRelease: Decodable {
        let assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browser_download_url: String
    }
}

public enum HK4eProtonExtrasError: LocalizedError {
    case noSidecarAsset
    case missingContentLength
    case installFailed

    public var errorDescription: String? {
        switch self {
        case .noSidecarAsset:
            return "Cannot find a YAAGL app tarball asset containing sidecar/protonextras."
        case .missingContentLength:
            return "Missing Content-Length while downloading protonextras."
        case .installFailed:
            return "Failed to install protonextras."
        }
    }
}
