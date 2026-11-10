//
//  YotoAPIClient.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import Foundation

enum YotoAPIError: Error {
    case badResponse
}

/// Talks to the unauthenticated parts of api.yotoplay.com needed to list and resolve
/// free/built-in radio stations. See RADIO_REVERSE_ENGINEERING_REPORT.md:
///   GET /card/library/free  -> filter metadata.category == "radio"
///   GET /card/{cardId}      -> chapters[].tracks[] where type == "stream" -> trackUrl
final class YotoAPIClient {
    static let shared = YotoAPIClient()

    private let baseURL = URL(string: "https://api.yotoplay.com")!
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchRadioStations() async throws -> [RadioStation] {
        let summaries = try await fetchFreeLibrary()
        let radioCards = summaries.filter {
            ($0.metadata?.category ?? "").caseInsensitiveCompare("radio") == .orderedSame
        }

        guard !radioCards.isEmpty else { return [] }

        return await withTaskGroup(of: [RadioStation].self) { group in
            for summary in radioCards {
                group.addTask {
                    await self.stations(
                        forCardId: summary.cardId,
                        fallbackTitle: summary.title,
                        fallbackIconURLString: summary.metadata?.cover?.imageL
                    )
                }
            }

            var all: [RadioStation] = []
            for await stations in group {
                all.append(contentsOf: stations)
            }
            return Self.sortedByDevicePreference(all)
        }
    }

    /// Orders stations: Yoto-branded ones first, then stations tagged with one of the
    /// device's configured languages, then everything else — alphabetical within each group.
    /// No separate per-country request is needed for the language tier — /card/library/free
    /// already returns the full catalog with per-card `languages` tags in one shot.
    private static func sortedByDevicePreference(_ stations: [RadioStation]) -> [RadioStation] {
        let preferredLanguages = Set(
            Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        )

        func rank(_ station: RadioStation) -> Int {
            if station.title.range(of: "yoto", options: .caseInsensitive) != nil { return 0 }
            if !preferredLanguages.isDisjoint(with: station.languages) { return 1 }
            return 2
        }

        return stations.sorted { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.title < rhs.title
        }
    }

    private func stations(forCardId cardId: String, fallbackTitle: String?, fallbackIconURLString: String?) async -> [RadioStation] {
        do {
            let detail = try await fetchCardDetail(cardId: cardId)
            return Self.flatten(detail: detail, fallbackTitle: fallbackTitle, fallbackIconURLString: fallbackIconURLString)
        } catch {
            // One bad/unreachable card shouldn't take down the whole list.
            return []
        }
    }

    private func fetchFreeLibrary() async throws -> [CardSummary] {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("card/library/free"))
        try Self.validate(response)
        return try Self.decodeLibrary(data)
    }

    private func fetchCardDetail(cardId: String) async throws -> CardDetail {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("card/\(cardId)"))
        try Self.validate(response)
        return try Self.decodeCardDetail(data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YotoAPIError.badResponse
        }
    }

    private static func decodeLibrary(_ data: Data) throws -> [CardSummary] {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(LibraryFreeResponse.self, from: data), let cards = wrapped.cards {
            return cards
        }
        return try decoder.decode([CardSummary].self, from: data)
    }

    private static func decodeCardDetail(_ data: Data) throws -> CardDetail {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(CardDetailResponse.self, from: data), let card = wrapped.card {
            return card
        }
        return try decoder.decode(CardDetail.self, from: data)
    }

    private static func flatten(detail: CardDetail, fallbackTitle: String?, fallbackIconURLString: String?) -> [RadioStation] {
        guard let chapters = detail.content?.chapters else { return [] }

        let cardTitle = detail.title ?? fallbackTitle ?? String(localized: "Radio")
        let cardIconString = detail.metadata?.cover?.imageL ?? fallbackIconURLString
        let languages = detail.metadata?.languages ?? []

        // Some chapters alias the exact same stream under a different key (legacy naming);
        // keep only the first occurrence of each URL.
        var seenURLs = Set<URL>()
        let candidates: [(chapter: CardChapter, track: CardTrack, url: URL)] = chapters.compactMap { chapter in
            guard let tracks = chapter.tracks,
                  let streamTrack = tracks.first(where: { $0.type == "stream" }),
                  let urlString = streamTrack.trackUrl,
                  let url = URL(string: urlString),
                  seenURLs.insert(url).inserted else { return nil }
            return (chapter, streamTrack, url)
        }

        // A card that *is* a single station (e.g. "Radio Yoto (FR)") should be shown under its
        // own descriptive card title rather than a generic/duplicate chapter title. A card that
        // bundles several stations as chapters (e.g. "BBC Radio" -> Radio 1/Radio 2/6 Music) needs
        // the chapter's own title to tell them apart.
        let titleCounts = Dictionary(candidates.map { ($0.chapter.title ?? cardTitle, 1) }, uniquingKeysWith: +)

        return candidates.map { candidate in
            let title: String
            if candidates.count == 1 {
                title = cardTitle
            } else {
                let chapterTitle = candidate.chapter.title ?? cardTitle
                title = Self.disambiguated(chapterTitle, key: candidate.chapter.key, isDuplicate: (titleCounts[chapterTitle] ?? 1) > 1)
            }

            let iconString = httpIconString(candidate.chapter.display?.icon16x16) ?? cardIconString
            let id = "\(detail.cardId)/\(candidate.chapter.key ?? candidate.track.key ?? title)"

            return RadioStation(
                id: id,
                cardId: detail.cardId,
                chapterKey: candidate.chapter.key ?? "",
                title: title,
                streamURL: candidate.url,
                format: candidate.track.format,
                iconURLString: iconString,
                languages: languages
            )
        }
    }

    /// Appends a short disambiguator derived from the chapter key when two chapters in the
    /// same card share an identical title (e.g. two chapters both just called "Radio").
    private static func disambiguated(_ title: String, key: String?, isDuplicate: Bool) -> String {
        guard isDuplicate, let key, !key.isEmpty else { return title }
        let cleaned = key
            .replacingOccurrences(of: "radio-", with: "")
            .replacingOccurrences(of: "-", with: " ")
        guard !cleaned.isEmpty else { return title }
        return "\(title) (\(cleaned.capitalized))"
    }

    /// Yoto icons are sometimes referenced via an internal `yoto:#...` scheme rather than a
    /// downloadable URL. Only treat http(s) values as usable artwork.
    private static func httpIconString(_ raw: String?) -> String? {
        guard let raw, let scheme = URL(string: raw)?.scheme, scheme == "http" || scheme == "https" else {
            return nil
        }
        return raw
    }
}
