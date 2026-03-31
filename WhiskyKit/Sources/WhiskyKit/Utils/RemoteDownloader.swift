//
//  RemoteDownloader.swift
//  WhiskyKit
//

import Foundation

public enum RemoteDownloader {
    private static var fm: FileManager { FileManager.default }

    public struct DownloadError: LocalizedError, Sendable {
        public enum Kind: Sendable {
            case httpStatus(Int)
            case notConnected
            case timedOut
            case dns
            case network
            case cancelled
            case noSpace
            case unknown
        }

        public let kind: Kind
        public let underlying: Error?

        public init(_ kind: Kind, underlying: Error? = nil) {
            self.kind = kind
            self.underlying = underlying
        }

        public var errorDescription: String? {
            userFacingDescription
        }

        public var userFacingDescription: String {
            switch kind {
            case .httpStatus(404):
                return String(localized: "runtime.error.notFound")
            case .httpStatus(410):
                return String(localized: "runtime.error.notFound")
            case .httpStatus:
                return String(localized: "runtime.error.unavailable")
            case .notConnected:
                return String(localized: "runtime.error.noInternet")
            case .timedOut:
                return String(localized: "runtime.error.timedOut")
            case .dns:
                return String(localized: "runtime.error.dns")
            case .network:
                return String(localized: "runtime.error.network")
            case .cancelled:
                return String(localized: "runtime.error.cancelled")
            case .noSpace:
                return String(localized: "runtime.error.noSpace")
            case .unknown:
                return String(localized: "runtime.error.generic")
            }
        }
    }

    public static func downloadOnce(
        url: URL,
        destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil,
        timeoutIntervalForRequest: TimeInterval = 30,
        timeoutIntervalForResource: TimeInterval = 60 * 60,
        retries: Int = 3
    ) async throws {
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            progress?(1)
            return
        }

        let parent = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path(percentEncoded: false)) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                try await downloadOnceInternal(
                    url: url,
                    destination: destination,
                    progress: progress,
                    timeoutIntervalForRequest: timeoutIntervalForRequest,
                    timeoutIntervalForResource: timeoutIntervalForResource
                )
                return
            } catch is CancellationError {
                throw DownloadError(.cancelled)
            } catch {
                attempt += 1
                let mapped = mapError(error)
                if attempt > retries || !shouldRetry(mapped.kind) {
                    throw mapped
                }
                let delaySeconds = min(pow(2, Double(attempt - 1)), 8)
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
    }

    private static func downloadOnceInternal(
        url: URL,
        destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        timeoutIntervalForRequest: TimeInterval,
        timeoutIntervalForResource: TimeInterval
    ) async throws {
        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutIntervalForRequest
        config.timeoutIntervalForResource = timeoutIntervalForResource
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let task = session.downloadTask(with: url)
        try await withTaskCancellationHandler(operation: {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                delegate.continuation = cont
                task.resume()
            }
        }, onCancel: {
            task.cancel()
        })

        if let status = delegate.httpStatusCode, status >= 400 {
            throw DownloadError(.httpStatus(status))
        }
    }

    private static func shouldRetry(_ kind: DownloadError.Kind) -> Bool {
        switch kind {
        case .timedOut, .dns, .network, .notConnected:
            return true
        case .httpStatus(let code):
            return code == 429 || (code >= 500 && code <= 599)
        case .cancelled, .noSpace, .unknown:
            return false
        }
    }

    private static func mapError(_ error: Error) -> DownloadError {
        if let error = error as? DownloadError {
            return error
        }
        if error is CancellationError {
            return DownloadError(.cancelled)
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet:
                return DownloadError(.notConnected, underlying: error)
            case .timedOut:
                return DownloadError(.timedOut, underlying: error)
            case .cannotFindHost, .dnsLookupFailed:
                return DownloadError(.dns, underlying: error)
            case .cannotConnectToHost, .networkConnectionLost:
                return DownloadError(.network, underlying: error)
            case .cancelled:
                return DownloadError(.cancelled, underlying: error)
            default:
                return DownloadError(.unknown, underlying: error)
            }
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return DownloadError(.noSpace, underlying: error)
        }
        return DownloadError(.unknown, underlying: error)
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let destination: URL
        let progress: (@Sendable (Double) -> Void)?
        var continuation: CheckedContinuation<Void, Error>?
        var httpStatusCode: Int? = nil
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
                if let http = downloadTask.response as? HTTPURLResponse {
                    httpStatusCode = http.statusCode
                    if http.statusCode >= 400 {
                        if let continuation {
                            self.continuation = nil
                            continuation.resume(throwing: DownloadError(.httpStatus(http.statusCode)))
                        }
                        return
                    }
                }

                if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: location, to: destination)
                progress?(1)
                if let continuation {
                    self.continuation = nil
                    continuation.resume(returning: ())
                }
            } catch {
                if let continuation {
                    self.continuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let continuation else { return }
            self.continuation = nil
            if let error {
                continuation.resume(throwing: error)
            }
        }
    }
}
