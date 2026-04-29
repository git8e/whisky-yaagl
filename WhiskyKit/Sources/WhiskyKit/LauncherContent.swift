import Foundation

public struct HoYoPlayContent: Hashable, Sendable, Codable {
    public var displayName: String
    public var iconURL: URL?
    public var installerURL: URL?
    public var fallbackInstallerURL: URL?
    public var manualDownloadURL: URL?
    public var detectionPaths: [String]

    public init(
        displayName: String,
        iconURL: URL?,
        installerURL: URL?,
        fallbackInstallerURL: URL?,
        manualDownloadURL: URL?,
        detectionPaths: [String] = []
    ) {
        self.displayName = displayName
        self.iconURL = iconURL
        self.installerURL = installerURL
        self.fallbackInstallerURL = fallbackInstallerURL
        self.manualDownloadURL = manualDownloadURL
        self.detectionPaths = detectionPaths
    }

    public func isInstalled(in bottle: Bottle) -> Bool {
        let fm = FileManager.default

        for relativePath in detectionPaths {
            let normalized = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !normalized.isEmpty else { continue }

            let url = bottle.url.appending(path: normalized, directoryHint: .notDirectory)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    return true
                }

                let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                while let child = enumerator?.nextObject() as? URL {
                    var childIsDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: child.path(percentEncoded: false), isDirectory: &childIsDirectory),
                          !childIsDirectory.boolValue else { continue }
                    if child.lastPathComponent.caseInsensitiveCompare("HYP.exe") == .orderedSame {
                        return true
                    }
                }
            }
        }

        return bottle.programs.contains { program in
            let path = program.url.path(percentEncoded: false).lowercased()
            return path.contains("/hoyoplay/") || program.name.caseInsensitiveCompare("HYP.exe") == .orderedSame
        }
    }
}

public enum LauncherContent {
    private static let lock = NSLock()
    private static let manifestURL = URL(string: "https://raw.githubusercontent.com/git8e/whisky-yaagl/master/launcher-content.json")!
    private static let allowedManifestHosts: Set<String> = ["raw.githubusercontent.com"]
    private static let allowedContentHostSuffixes = ["hoyoverse.com", "github.com"]
    private static let manifestCacheTTL: TimeInterval = 12 * 60 * 60
    nonisolated(unsafe) private static var cachedManifest = ManifestStore(initialManifest: fallbackManifest)

    public static var hoyoPlay: HoYoPlayContent? {
        lock.lock()
        defer { lock.unlock() }
        return cachedManifest.manifest.hoyoPlay
    }

    public static func refreshIfNeeded() async {
        let shouldRefresh: Bool = lock.withLock {
            guard let lastRefresh = cachedManifest.lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) >= manifestCacheTTL
        }
        guard shouldRefresh else { return }
        _ = await refresh(forceRemote: false)
    }

    @discardableResult
    public static func refresh(forceRemote: Bool) async -> HoYoPlayContent? {
        if let remoteManifest = await loadRemoteManifestIfNeeded(forceRemote: forceRemote) {
            updateManifest(remoteManifest, refreshedAt: Date())
            return remoteManifest.hoyoPlay
        }

        if let cached = loadManifestFromDisk() {
            updateManifest(cached, refreshedAt: nil)
            return cached.hoyoPlay
        }

        updateManifest(fallbackManifest, refreshedAt: nil)
        return fallbackManifest.hoyoPlay
    }

    private static func loadRemoteManifestIfNeeded(forceRemote: Bool) async -> ContentManifest? {
        if !forceRemote, let cached = lock.withLock({ cachedManifest.lastRefresh }),
           Date().timeIntervalSince(cached) < manifestCacheTTL {
            return nil
        }

        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(from: manifestURL)
            guard isAllowedManifestResponse(response) else {
                return nil
            }
            let manifest = try JSONDecoder().decode(ContentManifest.self, from: data).sanitized()
            try persistManifestToDisk(manifest, data: data)
            return manifest
        } catch {
            return nil
        }
    }

    private static func updateManifest(_ manifest: ContentManifest, refreshedAt: Date?) {
        let sanitized = manifest.sanitized()
        lock.withLock {
            cachedManifest = ManifestStore(initialManifest: sanitized, lastRefresh: refreshedAt ?? cachedManifest.lastRefresh)
        }
    }

    private static func loadManifestFromDisk() -> ContentManifest? {
        guard let data = try? Data(contentsOf: manifestCacheURL),
              let manifest = try? JSONDecoder().decode(ContentManifest.self, from: data) else {
            return nil
        }
        return manifest.sanitized()
    }

    private static func persistManifestToDisk(_ manifest: ContentManifest, data: Data) throws {
        let folder = manifestCacheURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let encoded = (try? JSONEncoder().encode(manifest)) ?? data
        try encoded.write(to: manifestCacheURL, options: .atomic)
    }

    private static var manifestCacheURL: URL {
        WhiskyPaths.applicationSupportRoot
            .appending(path: "LauncherContent", directoryHint: .isDirectory)
            .appending(path: "launcher-content-cache")
            .appendingPathExtension("json")
    }

    private static var fallbackManifest: ContentManifest {
        guard let url = Bundle.module.url(forResource: "launcher-content-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ContentManifest.self, from: data) else {
            return ContentManifest(schemaVersion: 1, generatedAt: nil, hoyoPlay: nil)
        }
        return manifest.sanitized()
    }

    private static func isAllowedManifestResponse(_ response: URLResponse) -> Bool {
        guard let url = response.url else { return false }
        return url.scheme == "https" && allowedManifestHosts.contains(url.host() ?? "")
    }

    private static func isAllowedContentURL(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host()?.lowercased() else {
            return false
        }
        return allowedContentHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
    }

    private struct ManifestStore {
        var manifest: ContentManifest
        var lastRefresh: Date?

        init(initialManifest: ContentManifest, lastRefresh: Date? = nil) {
            manifest = initialManifest
            self.lastRefresh = lastRefresh
        }
    }

    private struct ContentManifest: Codable {
        var schemaVersion: Int = 1
        var generatedAt: String?
        var hoyoPlay: HoYoPlayContent?

        func sanitized() -> ContentManifest {
            guard var hoyoPlay else {
                return ContentManifest(schemaVersion: schemaVersion, generatedAt: generatedAt, hoyoPlay: nil)
            }

            let trimmedName = hoyoPlay.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            hoyoPlay.displayName = trimmedName.isEmpty ? "Install HoYoPlay" : trimmedName

            if !LauncherContent.isAllowedContentURL(hoyoPlay.iconURL) {
                hoyoPlay.iconURL = nil
            }

            guard LauncherContent.isAllowedContentURL(hoyoPlay.installerURL),
                  LauncherContent.isAllowedContentURL(hoyoPlay.fallbackInstallerURL),
                  LauncherContent.isAllowedContentURL(hoyoPlay.manualDownloadURL) else {
                return ContentManifest(schemaVersion: schemaVersion, generatedAt: generatedAt, hoyoPlay: nil)
            }

            hoyoPlay.detectionPaths = hoyoPlay.detectionPaths
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return ContentManifest(schemaVersion: schemaVersion, generatedAt: generatedAt, hoyoPlay: hoyoPlay)
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
