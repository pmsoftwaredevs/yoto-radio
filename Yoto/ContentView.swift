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
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.stations) { station in
                        Button {
                            playback.play(station)
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
}

#Preview {
    ContentView()
}
