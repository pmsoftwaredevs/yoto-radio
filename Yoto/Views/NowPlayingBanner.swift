//
//  NowPlayingBanner.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import SwiftUI

/// Bottom mini-player. Only ever shown while `PlaybackManager` has a loaded station —
/// tapping it opens the full "Currently Playing" sheet.
struct NowPlayingBanner: View {
    @ObservedObject var playback: PlaybackManager

    var body: some View {
        if let station = playback.currentStation {
            HStack(spacing: 12) {
                stationIcon(for: station)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(playback.isCasting ? "Casting" : (playback.isBuffering ? "Buffering…" : "Playing"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func stationIcon(for station: RadioStation) -> some View {
        if let iconURL = station.iconURL {
            AsyncImage(url: iconURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
            }
        } else {
            Image(systemName: "dot.radiowaves.left.and.right")
        }
    }
}
