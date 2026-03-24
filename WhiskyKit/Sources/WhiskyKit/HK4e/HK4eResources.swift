//
//  HK4eResources.swift
//  WhiskyKit
//

import Foundation

public enum HK4eResources {
    private static var fm: FileManager { FileManager.default }

    public static var rootDir: URL {
        WhiskyPaths.applicationSupportRoot.appending(path: "HK4e", directoryHint: .isDirectory)
    }

    public static var dxmtDir: URL { rootDir.appending(path: "dxmt", directoryHint: .isDirectory) }
    public static var dxvkDir: URL { rootDir.appending(path: "dxvk", directoryHint: .isDirectory) }
    public static var reshadeDir: URL { rootDir.appending(path: "reshade", directoryHint: .isDirectory) }

    public static func ensureDirs() throws {
        for dir in [rootDir, dxmtDir, dxvkDir, reshadeDir] {
            if !fm.fileExists(atPath: dir.path(percentEncoded: false)) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}

public enum HK4eDownloader {
    private static var fm: FileManager { FileManager.default }

    public static func downloadOnce(
        url: URL,
        destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            progress?(1)
            return
        }

        if !fm.fileExists(atPath: destination.deletingLastPathComponent().path(percentEncoded: false)) {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let task = session.downloadTask(with: url)
        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            delegate.continuation = cont
            task.resume()
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        let destination: URL
        let progress: (@Sendable (Double) -> Void)?
        var continuation: CheckedContinuation<Void, Error>?
        private var fm: FileManager { FileManager.default }

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
                if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                    continuation?.resume(returning: ())
                    continuation = nil
                    return
                }
                try fm.moveItem(at: location, to: destination)
                progress?(1)
                continuation?.resume(returning: ())
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
}
