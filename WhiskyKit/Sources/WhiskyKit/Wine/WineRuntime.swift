//
//  WineRuntime.swift
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

public struct WineRuntime: Identifiable, Hashable, Sendable, Codable {
    public enum RenderBackend: String, Hashable, Sendable, Codable {
        case dxmt
    }

    public struct ArchiveLayout: Hashable, Sendable, Codable {
        public var winePathInArchive: String?

        public init(winePathInArchive: String?) {
            self.winePathInArchive = winePathInArchive
        }
    }

    public var id: String
    public var track: String
    public var displayName: String
    public var version: String
    public var revision: Int
    public var remoteURL: URL?
    public var renderBackend: RenderBackend?
    public var archive: ArchiveLayout
    public var recommended: Bool

    public init(
        id: String,
        track: String,
        displayName: String,
        version: String,
        revision: Int,
        remoteURL: URL?,
        renderBackend: RenderBackend? = nil,
        archive: ArchiveLayout,
        recommended: Bool = false
    ) {
        self.id = id
        self.track = track
        self.displayName = displayName
        self.version = version
        self.revision = revision
        self.remoteURL = remoteURL
        self.renderBackend = renderBackend
        self.archive = archive
        self.recommended = recommended
    }
}

public struct WineRuntimeUpdate: Hashable, Sendable {
    public let installed: WineRuntime
    public let latest: WineRuntime
}

public enum WineRuntimes {
    public static let whiskyDefaultId = "whisky"
    public static let didUpdateNotification = Notification.Name("WineRuntimesDidUpdate")

    private static let lock = NSLock()
    private static let manifestURL = URL(string: "https://raw.githubusercontent.com/git8e/whisky-yaagl/main/wine-runtimes.json")!
    private static let allowedManifestHosts: Set<String> = ["raw.githubusercontent.com"]
    private static let allowedRuntimeDownloadHosts: Set<String> = [
        "github.com",
        "raw.githubusercontent.com",
        "objects.githubusercontent.com",
        "data.getwhisky.app"
    ]
    private static let manifestCacheTTL: TimeInterval = 12 * 60 * 60
    nonisolated(unsafe) private static var cachedManifest = ManifestStore(initialManifest: fallbackManifest)

    public static var all: [WineRuntime] {
        lock.lock()
        defer { lock.unlock() }
        return cachedManifest.manifest.runtimes
    }

    public static var defaultRuntimeId: String {
        lock.lock()
        defer { lock.unlock() }
        return cachedManifest.manifest.defaultRuntimeId
    }

    public static func runtime(id: String) -> WineRuntime? {
        all.first(where: { $0.id == id })
    }

    public static var preferredSetupRuntime: WineRuntime? {
        let runtimes = all
        if let recommended = runtimes.first(where: { $0.recommended && $0.renderBackend == .dxmt }) {
            return recommended
        }
        return runtimes.first(where: { $0.id != whiskyDefaultId })
    }

    public static var setupRuntimeIds: [String] {
        if let preferredSetupRuntime {
            return [preferredSetupRuntime.id]
        }
        return []
    }

    public static func refreshCatalogIfNeeded() async {
        let shouldRefresh: Bool = lock.withLock {
            guard let lastRefresh = cachedManifest.lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) >= manifestCacheTTL
        }
        guard shouldRefresh else { return }
        _ = await refreshCatalog(forceRemote: false)
    }

    @discardableResult
    public static func refreshCatalog(forceRemote: Bool) async -> [WineRuntime] {
        if let remoteManifest = await loadRemoteManifestIfNeeded(forceRemote: forceRemote) {
            updateManifest(remoteManifest, refreshedAt: Date())
            return remoteManifest.runtimes
        }

        if let cached = loadManifestFromDisk() {
            updateManifest(cached, refreshedAt: nil)
            return cached.runtimes
        }

        updateManifest(fallbackManifest, refreshedAt: nil)
        return fallbackManifest.runtimes
    }

    public static func availableInstalledUpdates() async -> [WineRuntimeUpdate] {
        let runtimes = await refreshCatalog(forceRemote: true)
        let installed = runtimes.filter { WineRuntimeManager.isInstalled(runtimeId: $0.id) }
        let latestByTrack = Dictionary(grouping: runtimes, by: \.track)
            .compactMapValues { candidates in
                candidates.max(by: { lhs, rhs in
                    isOlderRuntime(lhs, than: rhs)
                })
            }

        return installed.compactMap { runtime in
            guard let latest = latestByTrack[runtime.track], isOlderRuntime(runtime, than: latest) else {
                return nil
            }
            return WineRuntimeUpdate(installed: runtime, latest: latest)
        }
        .sorted { lhs, rhs in
            lhs.latest.displayName.localizedStandardCompare(rhs.latest.displayName) == .orderedAscending
        }
    }

    private static func loadRemoteManifestIfNeeded(forceRemote: Bool) async -> RuntimeManifest? {
        if !forceRemote, let cached = lock.withLock({ cachedManifest.lastRefresh }),
           Date().timeIntervalSince(cached) < manifestCacheTTL {
            return nil
        }

        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(from: manifestURL)
            guard isAllowedManifestResponse(response) else {
                return nil
            }
            let manifest = try JSONDecoder().decode(RuntimeManifest.self, from: data).sanitized()
            try persistManifestToDisk(manifest, data: data)
            return manifest
        } catch {
            return nil
        }
    }

    private static func updateManifest(_ manifest: RuntimeManifest, refreshedAt: Date?) {
        let sanitized = manifest.sanitized()
        lock.withLock {
            cachedManifest = ManifestStore(initialManifest: sanitized, lastRefresh: refreshedAt ?? cachedManifest.lastRefresh)
        }
        NotificationCenter.default.post(name: didUpdateNotification, object: nil)
    }

    private static func loadManifestFromDisk() -> RuntimeManifest? {
        guard let data = try? Data(contentsOf: manifestCacheURL),
              let manifest = try? JSONDecoder().decode(RuntimeManifest.self, from: data) else {
            return nil
        }
        return manifest.sanitized()
    }

    private static func persistManifestToDisk(_ manifest: RuntimeManifest, data: Data) throws {
        let folder = manifestCacheURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let encoded = (try? JSONEncoder().encode(manifest)) ?? data
        try encoded.write(to: manifestCacheURL, options: .atomic)
    }

    private static var manifestCacheURL: URL {
        WhiskyPaths.applicationSupportRoot
            .appending(path: "Wine", directoryHint: .isDirectory)
            .appending(path: "wine-runtimes-cache.json")
    }

    private static var fallbackManifest: RuntimeManifest {
        guard let url = Bundle.module.url(forResource: "wine-runtimes-fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(RuntimeManifest.self, from: data) else {
            return RuntimeManifest(schemaVersion: 1, generatedAt: nil, defaultRuntimeId: whiskyDefaultId, runtimes: [])
        }
        return manifest.sanitized()
    }

    private static func isOlderRuntime(_ lhs: WineRuntime, _ rhs: WineRuntime) -> Bool {
        isOlderRuntime(lhs, than: rhs)
    }

    private static func isOlderRuntime(_ lhs: WineRuntime, than rhs: WineRuntime) -> Bool {
        let lhsVersion = versionComponents(lhs.version)
        let rhsVersion = versionComponents(rhs.version)
        let maxCount = max(lhsVersion.count, rhsVersion.count)

        for index in 0..<maxCount {
            let lhsComponent = index < lhsVersion.count ? lhsVersion[index] : 0
            let rhsComponent = index < rhsVersion.count ? rhsVersion[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent < rhsComponent
            }
        }

        return lhs.revision < rhs.revision
    }

    private static func versionComponents(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }

    private static func isAllowedManifestResponse(_ response: URLResponse) -> Bool {
        guard let url = response.url else { return false }
        return url.scheme == "https" && allowedManifestHosts.contains(url.host() ?? "")
    }

    private static func isAllowedRuntimeURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && allowedRuntimeDownloadHosts.contains(url.host() ?? "")
    }

    private struct ManifestStore {
        var manifest: RuntimeManifest
        var lastRefresh: Date?

        init(initialManifest: RuntimeManifest, lastRefresh: Date? = nil) {
            manifest = initialManifest
            self.lastRefresh = lastRefresh
        }
    }

    private struct RuntimeManifest: Codable {
        var schemaVersion: Int = 1
        var generatedAt: String?
        var defaultRuntimeId: String
        var runtimes: [WineRuntime]

        func sanitized() -> RuntimeManifest {
            let filtered = runtimes.filter { runtime in
                if runtime.id == WineRuntimes.whiskyDefaultId {
                    return WineRuntimes.isAllowedRuntimeURL(runtime.remoteURL)
                }
                return WineRuntimes.isAllowedRuntimeURL(runtime.remoteURL)
            }

            let deduped = Array(Dictionary(filtered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
                .sorted { lhs, rhs in
                    if lhs.recommended != rhs.recommended {
                        return lhs.recommended && !rhs.recommended
                    }
                    if lhs.id == WineRuntimes.whiskyDefaultId { return false }
                    if rhs.id == WineRuntimes.whiskyDefaultId { return true }
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }

            let defaultId = deduped.contains(where: { $0.id == defaultRuntimeId })
                ? defaultRuntimeId
                : deduped.first?.id ?? WineRuntimes.whiskyDefaultId

            return RuntimeManifest(schemaVersion: schemaVersion, generatedAt: generatedAt, defaultRuntimeId: defaultId, runtimes: deduped)
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
