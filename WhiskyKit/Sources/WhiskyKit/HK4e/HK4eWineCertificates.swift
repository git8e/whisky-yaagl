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

    // Certificate payload is bundled in the app resources. A remote fallback is kept for recovery.
    // Can be overridden via HK4E_WINE_INF_CERT_URL.
    private static let defaultCertURL = URL(
        string: "https://raw.githubusercontent.com/git8e/whisky-yaagl/main/assets/wine_inf_cert_str.txt"
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
        if let bundled = Bundle.main.url(forResource: "wine_inf_cert_str", withExtension: "txt") {
            let body = (try? String(contentsOf: bundled, encoding: .utf8)) ?? ""
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return body
            }
        }

        let url = ProcessInfo.processInfo.environment["HK4E_WINE_INF_CERT_URL"].flatMap(URL.init(string:)) ?? defaultCertURL

        var req = URLRequest(url: url)
        req.setValue("whisky-yaagl", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HK4eWineCertificatesError.httpError(code: http.statusCode, url: url.absoluteString)
        }
        let body = String(data: data, encoding: .utf8) ?? ""
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
    case httpError(code: Int, url: String)

    public var errorDescription: String? {
        switch self {
        case .certNotFound:
            return "Failed to fetch YAAGL WINE_INF_CERT_STR"
        case .wineInfMissing(let path):
            return "wine.inf not found: \(path)"
        case .httpError(let code, let url):
            return "Failed to download certificate payload (HTTP \(code)): \(url)"
        }
    }
}
