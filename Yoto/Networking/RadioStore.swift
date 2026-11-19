//
//  RadioStore.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import Combine
import Foundation

/// Cached radio catalog, kept for up to a week before it's considered stale.
private struct RadioCatalogCache: Codable {
    let stations: [RadioStation]
    let fetchedAt: Date
    /// Bump when the way stations are built changes, so stale caches are discarded.
    var version: Int? = Self.currentVersion

    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    static let currentVersion = 3

    var isFresh: Bool {
        version == Self.currentVersion && Date().timeIntervalSince(fetchedAt) < Self.maxAge
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("radio-catalog-cache.json")
    }

    static func load() -> RadioCatalogCache? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(RadioCatalogCache.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL)
    }
}

@MainActor
final class RadioStore: ObservableObject {
    @Published private(set) var stations: [RadioStation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasError = false

    func load() async {
        if let cache = RadioCatalogCache.load(), cache.isFresh {
            stations = cache.stations
            return
        }

        isLoading = true
        hasError = false
        do {
            let fetched = try await YotoAPIClient.shared.fetchRadioStations()
            stations = fetched
            RadioCatalogCache(stations: fetched, fetchedAt: Date()).save()
        } catch {
            hasError = true
        }
        isLoading = false
    }
}
