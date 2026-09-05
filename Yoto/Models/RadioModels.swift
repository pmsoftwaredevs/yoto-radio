//
//  RadioModels.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import Foundation

// MARK: - Yoto card API wire types
//
// Shapes reverse-engineered from RADIO_REVERSE_ENGINEERING_REPORT.md. Fields are optional
// throughout since the exact envelope/casing isn't guaranteed across every card, and Codable
// silently ignores JSON keys we don't declare.

struct CardCover: Codable {
    let imageL: String?
}

struct CardMedia: Codable {
    let hasStreams: Bool?
}

struct CardMetadata: Codable {
    let category: String?
    let cover: CardCover?
    let media: CardMedia?
    let languages: [String]?
}

struct CardSummary: Codable, Identifiable {
    let cardId: String
    let title: String?
    let availability: String?
    let metadata: CardMetadata?

    var id: String { cardId }
}

struct LibraryFreeResponse: Codable {
    let cards: [CardSummary]?
}

struct ChapterDisplay: Codable {
    let icon16x16: String?
}

struct CardTrack: Codable {
    let key: String?
    let title: String?
    let type: String?
    let format: String?
    let trackUrl: String?
}

struct CardChapter: Codable {
    let key: String?
    let title: String?
    let hasStreams: Bool?
    let tracks: [CardTrack]?
    let display: ChapterDisplay?
}

struct CardContent: Codable {
    let chapters: [CardChapter]?
}

struct CardDetail: Codable {
    let cardId: String
    let title: String?
    let metadata: CardMetadata?
    let content: CardContent?
}

struct CardDetailResponse: Codable {
    let card: CardDetail?
}

// MARK: - App-facing model

/// One playable radio station, flattened from a card chapter that has a "stream" track.
/// A card that bundles several stations as separate chapters (e.g. "BBC Radio" containing
/// Radio 1/Radio 2/6 Music/...) yields one RadioStation per chapter; a card that *is* a single
/// station (e.g. "Radio Yoto (FR)") yields one RadioStation using the card's own title.
struct RadioStation: Identifiable, Hashable, Codable {
    let id: String
    let cardId: String
    let chapterKey: String
    let title: String
    let streamURL: URL
    let format: String?
    let iconURLString: String?
    /// ISO language codes from the card's metadata (e.g. "fr", "en"), used to prioritize
    /// stations matching the languages configured on the device. Empty when untagged.
    let languages: [String]

    var iconURL: URL? {
        guard let iconURLString else { return nil }
        return URL(string: iconURLString)
    }
}
