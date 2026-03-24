//
//  HK4eWineCertificates.swift
//  WhiskyKit
//
//  Downloads the YAAGL Wine INF certificate section and patches wine.inf.
//  This matches YAAGL's approach (wine.inf patch) without bundling the certificate blob.
//

import Foundation

public enum HK4eWineCertificates {
    private static var fm: FileManager { FileManager.default }

    private static let markerBegin = "; YAAGL_WINE_INF_CERT_BEGIN"
    private static let markerEnd = "; YAAGL_WINE_INF_CERT_END"

    private static let secretURL = URL(
        string: "https://raw.githubusercontent.com/yaagl/yet-another-anime-game-launcher/main/src/clients/secret.ts"
    )!

    public static func ensurePatched(runtimeId: String) async throws {
        let wineInf = wineInfURL(runtimeId: runtimeId)
        guard fm.fileExists(atPath: wineInf.path(percentEncoded: false)) else {
            throw HK4eWineCertificatesError.wineInfMissing(wineInf.path(percentEncoded: false))
        }

        let current = (try? String(contentsOf: wineInf, encoding: .utf8)) ?? ""
        if current.contains(markerBegin) {
            return
        }

        let certSection = try await fetchWineInfCertSection()

        // Backup once.
        let bak = wineInf.appendingPathExtension("bak")
        if !fm.fileExists(atPath: bak.path(percentEncoded: false)) {
            try fm.copyItem(at: wineInf, to: bak)
        }

        var out = current
        if !out.hasSuffix("\n") { out += "\n" }
        out += "\n\(markerBegin)\n"
        out += certSection
        if !out.hasSuffix("\n") { out += "\n" }
        out += "\(markerEnd)\n"

        try out.write(to: wineInf, atomically: true, encoding: .utf8)
    }

    public static func revert(runtimeId: String) throws {
        let wineInf = wineInfURL(runtimeId: runtimeId)
        let bak = wineInf.appendingPathExtension("bak")
        if fm.fileExists(atPath: bak.path(percentEncoded: false)) {
            if fm.fileExists(atPath: wineInf.path(percentEncoded: false)) {
                try? fm.removeItem(at: wineInf)
            }
            try fm.copyItem(at: bak, to: wineInf)
            return
        }

        let current = (try? String(contentsOf: wineInf, encoding: .utf8)) ?? ""
        guard current.contains(markerBegin) else { return }
        if let range = current.range(of: markerBegin),
           let endRange = current.range(of: markerEnd)
        {
            var out = current
            out.removeSubrange(range.lowerBound..<endRange.upperBound)
            try out.write(to: wineInf, atomically: true, encoding: .utf8)
        }
    }

    private static func wineInfURL(runtimeId: String) -> URL {
        let root = WineRuntimeManager.wineRoot(runtimeId: runtimeId)
        return root
            .appending(path: "share", directoryHint: .isDirectory)
            .appending(path: "wine", directoryHint: .isDirectory)
            .appending(path: "wine.inf", directoryHint: .notDirectory)
    }

    private static func fetchWineInfCertSection() async throws -> String {
        let (data, _) = try await URLSession(configuration: .ephemeral).data(from: secretURL)
        let src = String(data: data, encoding: .utf8) ?? ""

        guard let start = src.range(of: "export const WINE_INF_CERT_STR") else {
            throw HK4eWineCertificatesError.certNotFound
        }
        let after = src[start.upperBound...]
        guard let tick1 = after.firstIndex(of: "`") else {
            throw HK4eWineCertificatesError.certNotFound
        }
        let rest = after[after.index(after: tick1)...]
        guard let tick2 = rest.firstIndex(of: "`") else {
            throw HK4eWineCertificatesError.certNotFound
        }

        let body = String(rest[..<tick2])
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw HK4eWineCertificatesError.certNotFound
        }
        return body
    }
}

public enum HK4eWineCertificatesError: LocalizedError {
    case certNotFound
    case wineInfMissing(String)

    public var errorDescription: String? {
        switch self {
        case .certNotFound:
            return "Failed to fetch YAAGL WINE_INF_CERT_STR"
        case .wineInfMissing(let path):
            return "wine.inf not found: \(path)"
        }
    }
}
