//
//  ContentView.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = RadioStore()
    @ObservedObject private var playback = PlaybackManager.shared
    @ObservedObject private var castManager = CastManager.shared
    @State private var showingNowPlaying = false
    @State private var selectedFilter: LanguageFilter = .all

    /// The app's own languages get a button each, the device's language first;
    /// every other language shares a single "Others" button.
    private static let mainLanguages: [String] = {
        Locale.current.language.languageCode?.identifier == "en" ? ["en", "fr"] : ["fr", "en"]
    }()

    private var visibleStations: [RadioStation] {
        store.stations.filter { selectedFilter.matches($0, mainLanguages: Self.mainLanguages) }
    }

    // Fixed 3-per-row layout: source icons are tiny (16x16), so smaller tiles mean less
    // upscaling and less visible pixelation than the wider adaptive tiles used before.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                content

                if playback.currentStation != nil {
                    NowPlayingBanner(playback: playback)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .onTapGesture { showingNowPlaying = true }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: playback.currentStation != nil)
            .navigationTitle("Radios")
            .task { await store.load() }
            .sheet(isPresented: $showingNowPlaying) {
                NowPlayingView(playback: playback, castManager: castManager)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.stations.isEmpty {
            ProgressView("Loading radios…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.hasError && store.stations.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Couldn't load radio stations. Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await store.load() } }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                languageFilterBar
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(visibleStations) { station in
                        Button {
                            playback.play(station, in: visibleStations)
                        } label: {
                            RadioTileView(station: station, isActive: playback.currentStation?.id == station.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .padding(.bottom, playback.currentStation != nil ? 72 : 0)
            }
            .refreshable { await store.load() }
        }
    }

    private var languageFilterBar: some View {
        FlowLayout(spacing: 8) {
                filterChip(String(localized: "All"), filter: .all)
                ForEach(Self.mainLanguages, id: \.self) { code in
                    filterChip(languageName(code), filter: .language(code))
                }
                filterChip(String(localized: "Others"), filter: .other)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func filterChip(_ title: String, filter: LanguageFilter) -> some View {
        let isSelected = selectedFilter == filter
        return Button { selectedFilter = filter } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func languageName(_ code: String) -> String {
        (Locale.current.localizedString(forLanguageCode: code) ?? code).localizedCapitalized
    }
}

enum LanguageFilter: Hashable {
    case all
    case language(String)
    case other

    func matches(_ station: RadioStation, mainLanguages: [String]) -> Bool {
        // Stations with no clear language (instrumental, multilingual) suit every listener,
        // so they show under each main language rather than in a category of their own.
        let isUnclear = station.languages.contains(RadioStation.internationalLanguageCode)
        switch self {
        case .all:
            return true
        case .language(let code):
            return isUnclear || station.languages.contains(code)
        case .other:
            return !isUnclear && !station.languages.contains(where: mainLanguages.contains)
        }
    }
}

#Preview {
    ContentView()
}

/// Lays children out left to right, wrapping onto new lines when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
