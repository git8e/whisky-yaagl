//
//  HK4eZip.swift
//  WhiskyKit
//

import Foundation

public enum HK4eZip {
    public static func extract(zipURL: URL, to destinationDir: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-x", "-k", zipURL.path(percentEncoded: false), destinationDir.path(percentEncoded: false)]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw HK4eZipError.extractFailed
        }
    }
}

public enum HK4eZipError: LocalizedError {
    case extractFailed

    public var errorDescription: String? {
        switch self {
        case .extractFailed:
            return "Failed to extract zip"
        }
    }
}
