import CryptoKit
import Foundation

public struct WineFont: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var displayName: String
    public var familyName: String
    public var fileName: String
    public var remoteURL: URL?
    public var sha256: String?
    public var aliases: [String]
}

public enum WineFonts {
    private static let lock = NSLock()
    private static let manifestURL = URL(string: "https://raw.githubusercontent.com/git8e/whisky-yaagl/master/font-catalog.json")!
    private static let allowedManifestHosts: Set<String> = ["raw.githubusercontent.com"]
    private static let allowedFontHosts: Set<String> = ["raw.githubusercontent.com"]
    private static let manifestCacheTTL: TimeInterval = 12 * 60 * 60
    nonisolated(unsafe) private static var cachedManifest = ManifestStore(initialManifest: fallbackManifest)

    public static var defaultFonts: [WineFont] {
        lock.withLock {
            let manifest = cachedManifest.manifest
            return manifest.defaultFontIds.compactMap { id in
                manifest.fonts.first(where: { $0.id == id })
            }
        }
    }

    public static func refreshCatalogIfNeeded() async {
        let shouldRefresh = lock.withLock {
            guard let lastRefresh = cachedManifest.lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) >= manifestCacheTTL
        }
        guard shouldRefresh else { return }
        _ = await refreshCatalog(forceRemote: false)
    }

    @discardableResult
    public static func refreshCatalog(forceRemote: Bool) async -> [WineFont] {
        if let remoteManifest = await loadRemoteManifestIfNeeded(forceRemote: forceRemote) {
            updateManifest(remoteManifest, refreshedAt: Date())
            return remoteManifest.fonts
        }

        if let cached = loadManifestFromDisk() {
            updateManifest(cached, refreshedAt: nil)
            return cached.fonts
        }

        updateManifest(fallbackManifest, refreshedAt: nil)
        return fallbackManifest.fonts
    }

    public static func ensureDefaultFontsInstalled(
        bottle: Bottle,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        _ = await refreshCatalog(forceRemote: false)
        let fonts = defaultFonts
        guard !fonts.isEmpty else { return }

        let fontsFolder = bottle.url
            .appending(path: "drive_c", directoryHint: .isDirectory)
            .appending(path: "windows", directoryHint: .isDirectory)
            .appending(path: "Fonts", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: fontsFolder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: fontsFolder, withIntermediateDirectories: true)
        }

        let marker = bottle.url.appending(path: ".whisky-yaagl-fonts-v1", directoryHint: .notDirectory)
        let allFontsInstalled = fonts.allSatisfy { font in
            let target = fontsFolder.appending(path: font.fileName, directoryHint: .notDirectory)
            return FileManager.default.fileExists(atPath: target.path(percentEncoded: false))
        }
        if allFontsInstalled && FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
            progress?(1)
            return
        }

        for (index, font) in fonts.enumerated() {
            try Task.checkCancellation()
            let target = fontsFolder.appending(path: font.fileName, directoryHint: .notDirectory)
            if !FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
                let cached = try await cachedFont(font: font) { fraction in
                    let base = Double(index) / Double(fonts.count)
                    progress?(base + fraction / Double(fonts.count))
                }
                try FileCopy.copyItem(at: cached, to: target, replacing: true)
            }
            progress?(Double(index + 1) / Double(fonts.count))
        }

        do {
            for await _ in try Wine.runWineserverProcess(args: ["-w"], bottle: bottle) { }
        } catch {
            // Best-effort: font installation must not block or break normal usage.
        }

        try await importFontSubstitutes(fonts: fonts, bottle: bottle)
        try? "1\n".write(to: marker, atomically: true, encoding: .utf8)
    }

    private static func cachedFont(font: WineFont, progress: (@Sendable (Double) -> Void)?) async throws -> URL {
        guard let remoteURL = font.remoteURL else {
            throw WineFontsError.missingRemoteURL(font.id)
        }

        let destination = fontCacheFolder
            .appending(path: font.id, directoryHint: .isDirectory)
            .appending(path: font.fileName, directoryHint: .notDirectory)

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            do {
                try await verifyFontIfNeeded(font: font, url: destination)
                progress?(1)
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
            }
        }

        try await RemoteDownloader.downloadOnce(url: remoteURL, destination: destination, progress: progress)
        try await verifyFontIfNeeded(font: font, url: destination)
        return destination
    }

    private static func importFontSubstitutes(fonts: [WineFont], bottle: Bottle) async throws {
        let pairs = fonts.flatMap { font in
            font.aliases.map { (alias: $0, familyName: font.familyName) }
        }
        guard !pairs.isEmpty else { return }

        let regURL = WhiskyWineInstaller.applicationFolder
            .appending(path: "Temp", directoryHint: .isDirectory)
            .appending(path: "FontSubstitutes-\(UUID().uuidString).reg", directoryHint: .notDirectory)
        if !FileManager.default.fileExists(atPath: regURL.deletingLastPathComponent().path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: regURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: regURL) }

        var reg = "Windows Registry Editor Version 5.00\n\n"
        reg += "[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]\n"
        for pair in pairs {
            reg += "\"\(escapeRegString(pair.alias))\"=\"\(escapeRegString(pair.familyName))\"\n"
        }
        reg += "\n[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes]\n"
        for pair in pairs {
            reg += "\"\(escapeRegString(pair.alias))\"=\"\(escapeRegString(pair.familyName))\"\n"
        }

        var data = Data([0xff, 0xfe])
        data.append(reg.data(using: .utf16LittleEndian) ?? Data())
        try data.write(to: regURL, options: .atomic)

        _ = try await Wine.runWine(["regedit", "/S", regURL.path(percentEncoded: false)], bottle: bottle)
    }

    private static func verifyFontIfNeeded(font: WineFont, url: URL) async throws {
        guard let expected = font.sha256?.trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty else {
            return
        }

        let computed = try await Task.detached(priority: .utility) {
            try computeSHA256(url: url)
        }.value
        if computed.lowercased() != expected.lowercased() {
            try? FileManager.default.removeItem(at: url)
            throw WineFontsError.integrityCheckFailed(font.id)
        }
    }

    private static func loadRemoteManifestIfNeeded(forceRemote: Bool) async -> FontManifest? {
        if !forceRemote, let cached = lock.withLock({ cachedManifest.lastRefresh }),
           Date().timeIntervalSince(cached) < manifestCacheTTL {
            return nil
        }

        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(from: manifestURL)
            guard isAllowedManifestResponse(response) else { return nil }
            let manifest = try JSONDecoder().decode(FontManifest.self, from: data).sanitized()
            try persistManifestToDisk(manifest, data: data)
            return manifest
        } catch {
            return nil
        }
    }

    private static func updateManifest(_ manifest: FontManifest, refreshedAt: Date?) {
        let sanitized = manifest.sanitized()
        lock.withLock {
            cachedManifest = ManifestStore(initialManifest: sanitized, lastRefresh: refreshedAt ?? cachedManifest.lastRefresh)
        }
    }

    private static func loadManifestFromDisk() -> FontManifest? {
        guard let data = try? Data(contentsOf: manifestCacheURL),
              let manifest = try? JSONDecoder().decode(FontManifest.self, from: data) else {
            return nil
        }
        return manifest.sanitized()
    }

    private static func persistManifestToDisk(_ manifest: FontManifest, data: Data) throws {
        let folder = manifestCacheURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let encoded = (try? JSONEncoder().encode(manifest)) ?? data
        try encoded.write(to: manifestCacheURL, options: .atomic)
    }

    private static var manifestCacheURL: URL {
        WhiskyPaths.applicationSupportRoot
            .appending(path: "Fonts", directoryHint: .isDirectory)
            .appending(path: "font-catalog-cache.json", directoryHint: .notDirectory)
    }

    private static var fontCacheFolder: URL {
        WhiskyPaths.applicationSupportRoot.appending(path: "Fonts", directoryHint: .isDirectory)
    }

    private static var fallbackManifest: FontManifest {
        guard let url = Bundle.module.url(forResource: "font-catalog-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(FontManifest.self, from: data) else {
            return FontManifest(schemaVersion: 1, generatedAt: nil, defaultFontIds: [], fonts: [])
        }
        return manifest.sanitized()
    }

    private static func isAllowedManifestResponse(_ response: URLResponse) -> Bool {
        guard let url = response.url else { return false }
        return url.scheme == "https" && allowedManifestHosts.contains(url.host() ?? "")
    }

    private static func isAllowedFontURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && allowedFontHosts.contains(url.host() ?? "")
    }

    private static func computeSHA256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func escapeRegString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private struct ManifestStore {
        var manifest: FontManifest
        var lastRefresh: Date?

        init(initialManifest: FontManifest, lastRefresh: Date? = nil) {
            manifest = initialManifest
            self.lastRefresh = lastRefresh
        }
    }

    private struct FontManifest: Codable {
        var schemaVersion: Int = 1
        var generatedAt: String?
        var defaultFontIds: [String]
        var fonts: [WineFont]

        func sanitized() -> FontManifest {
            let filtered = fonts.filter { font in
                !font.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !font.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !font.familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    WineFonts.isAllowedFontURL(font.remoteURL)
            }
            let deduped = Array(Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            let availableIds = Set(deduped.map(\.id))
            return FontManifest(
                schemaVersion: schemaVersion,
                generatedAt: generatedAt,
                defaultFontIds: defaultFontIds.filter { availableIds.contains($0) },
                fonts: deduped
            )
        }
    }
}

public enum WineFontsError: LocalizedError, Sendable {
    case missingRemoteURL(String)
    case integrityCheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRemoteURL(let id):
            return "Missing font download URL: \(id)"
        case .integrityCheckFailed(let id):
            return "Font integrity check failed: \(id)"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ action: () -> T) -> T {
        lock()
        defer { unlock() }
        return action()
    }
}
