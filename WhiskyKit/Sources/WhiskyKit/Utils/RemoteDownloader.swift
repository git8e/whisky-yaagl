//
//  RemoteDownloader.swift
//  WhiskyKit
//

import Foundation

public enum RemoteDownloader {
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

        let parent = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path(percentEncoded: false)) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
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

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: location, to: destination)
                progress?(1)
                continuation?.resume(returning: ())
            } catch {
                continuation?.resume(throwing: error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                continuation?.resume(throwing: error)
            }
        }
    }
}
