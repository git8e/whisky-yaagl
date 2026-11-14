//
//  Process+Extensions.swift
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

import Darwin
import Foundation
import os.log

public enum ProcessOutput: Hashable {
    case started(Process)
    case message(String)
    case error(String)
    case terminated(Process)
}

public extension Process {
    /// Run the process returning a stream output
    func runStream(name: String, fileHandle: FileHandle?) throws -> AsyncStream<ProcessOutput> {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let stream = makeStream(
            name: name,
            fileHandle: fileHandle,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )
        self.logProcessInfo(name: name)
        fileHandle?.writeInfo(for: self)
        do {
            try run()
            // Foundation keeps the parent's write end of a `Pipe` alive unless
            // it is closed explicitly. Leaving it open means the read end
            // never sees EOF, so commands that launch a detached Wine child
            // can keep the output stream alive forever.
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
        } catch {
            for pipe in [outputPipe, errorPipe] {
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
            throw error
        }
        return stream
    }

    private func makeStream(
        name: String,
        fileHandle: FileHandle?,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) -> AsyncStream<ProcessOutput> {
        standardOutput = outputPipe
        standardError = errorPipe

        return AsyncStream<ProcessOutput> { continuation in
            continuation.onTermination = { termination in
                switch termination {
                case .finished:
                    break
                case .cancelled:
                    guard self.isRunning else { return }
                    self.terminate()
                @unknown default:
                    break
                }
            }

            continuation.yield(.started(self))

            let outputReader = PipeOutputReader(
                pipe: outputPipe,
                continuation: continuation,
                isError: false,
                fileHandle: fileHandle
            )
            let errorReader = PipeOutputReader(
                pipe: errorPipe,
                continuation: continuation,
                isError: true,
                fileHandle: fileHandle
            )

            terminationHandler = { (process: Process) in
                // Finish the stream when the direct child exits. A Wine
                // launcher often leaves wineserver or the game holding the
                // inherited pipe, so waiting for EOF here would keep the
                // launch UI spinning until the game is closed.
                outputReader.processTerminated()
                errorReader.processTerminated()

                process.logTermination(name: name)
                continuation.yield(.terminated(process))
                continuation.finish()

                // If a detached child still owns a pipe, the readers stay
                // installed so the pipe keeps draining until EOF; they simply
                // stop forwarding output to the finished stream.
                outputReader.stopEmitting()
                errorReader.stopEmitting()
                try? fileHandle?.close()
            }
        }
    }

    private func logTermination(name: String) {
        if terminationStatus == 0 {
            Logger.wineKit.info(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        } else {
            Logger.wineKit.warning(
                "Terminated \(name) with status code '\(self.terminationStatus, privacy: .public)'"
            )
        }
    }

    private func logProcessInfo(name: String) {
        Logger.wineKit.info("Running process \(name)")

        if let arguments = arguments {
            Logger.wineKit.info("Arguments: `\(arguments.joined(separator: " "))`")
        }
        if let executableURL = executableURL {
            Logger.wineKit.info("Executable: `\(executableURL.path(percentEncoded: false))`")
        }
        if let directory = currentDirectoryURL {
            Logger.wineKit.info("Directory: `\(directory.path(percentEncoded: false))`")
        }
        if let environment = environment {
            Logger.wineKit.info("Environment: \(environment)")
        }
    }
}

/// Owns one process output pipe. The readability handler keeps draining the
/// pipe after the direct child exits so a detached Wine process does not block
/// on a full stdout/stderr buffer.
private final class PipeOutputReader: @unchecked Sendable {
    private let pipe: Pipe
    private let continuation: AsyncStream<ProcessOutput>.Continuation
    private let isError: Bool
    private let logHandle: FileHandle?
    private let readDescriptor: Int32
    private let queue: DispatchQueue
    private var emitting = true
    private var closed = false

    init(
        pipe: Pipe,
        continuation: AsyncStream<ProcessOutput>.Continuation,
        isError: Bool,
        fileHandle: FileHandle?
    ) {
        self.pipe = pipe
        self.continuation = continuation
        self.isError = isError
        self.logHandle = fileHandle
        self.readDescriptor = pipe.fileHandleForReading.fileDescriptor
        self.queue = DispatchQueue(label: "com.whisky.process-output.\(UUID().uuidString)")

        // Strong capture is intentional: the handler owns the pipe until EOF,
        // at which point the handler is removed and the cycle is broken.
        pipe.fileHandleForReading.readabilityHandler = { handle in
            self.queue.sync {
                self.readAvailable(from: handle)
            }
        }
    }

    private func readAvailable(from handle: FileHandle) {
        guard !closed else { return }

        let data = handle.availableData
        guard !data.isEmpty else {
            // EOF. Clearing the handler is essential: a readability source
            // stays active at EOF and would otherwise spin the CPU.
            closed = true
            handle.readabilityHandler = nil
            try? handle.close()
            return
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        emit(text)
    }

    private func emit(_ text: String) {
        guard emitting, !text.isEmpty else { return }

        continuation.yield(isError ? .error(text) : .message(text))
        if isError {
            Logger.wineKit.warning("\(text, privacy: .public)")
        } else {
            Logger.wineKit.info("\(text, privacy: .public)")
        }
        logHandle?.write(line: text)
    }

    /// Called when the direct child exits. Close the read end only when no
    /// other process (for example a detached game or wineserver) still owns
    /// the write end.
    func processTerminated() {
        queue.sync {
            guard !closed else { return }
            try? pipe.fileHandleForWriting.close()

            guard hasNoWriter() else {
                // A detached child inherited the pipe. Keep draining it until
                // EOF so it never blocks on a full pipe buffer.
                return
            }

            closed = true
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = nil
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { break }
                if let text = String(data: data, encoding: .utf8) {
                    emit(text)
                }
            }
            try? handle.close()
        }
    }

    func stopEmitting() {
        queue.sync {
            emitting = false
        }
    }

    private func hasNoWriter() -> Bool {
        var descriptor = pollfd(
            fd: readDescriptor,
            events: Int16(POLLIN | POLLHUP),
            revents: 0
        )
        let result = poll(&descriptor, 1, 0)
        guard result > 0 else { return false }
        return (descriptor.revents & Int16(POLLHUP)) != 0
            || (descriptor.revents & Int16(POLLNVAL)) != 0
    }
}
