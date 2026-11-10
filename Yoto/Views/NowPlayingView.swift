//
//  NowPlayingView.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import SwiftUI

/// Full "Currently Playing" screen, opened from the bottom banner.
/// Local playback and AirPlay behave normally (system handles routing/volume) — the only
/// custom control surfaced here is the volume overlay, and only while a Cast session is active.
struct NowPlayingView: View {
    @ObservedObject var playback: PlaybackManager
    @ObservedObject var castManager: CastManager
    @Environment(\.dismiss) private var dismiss

    @State private var localVolume: Double = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                artwork

                VStack(spacing: 4) {
                    Text(playback.currentStation?.title ?? "")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let summary = playback.trackSummary {
                        Text(summary)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 72))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 48) {
                    VStack(spacing: 6) {
                        AirPlayButton().frame(width: 30, height: 30)
                        Text("AirPlay").font(.caption2).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        CastButton().frame(width: 30, height: 30)
                        Text("Cast").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)
            }
            .padding()
            .navigationTitle("Currently Playing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // safeAreaInset reserves space and pushes the AirPlay/Cast row up, rather than
                // floating on top of it like .overlay did — that was covering the Cast button
                // as soon as a session connected, making it impossible to switch devices or
                // disconnect back to the phone.
                if castManager.isConnected {
                    castVolumeOverlay
                }
            }
        }
        .task { localVolume = Double(castManager.streamVolume) }
        .onChange(of: localVolume) { _, newValue in
            castManager.setVolume(Float(newValue))
        }
        .onChange(of: castManager.streamVolume) { _, newValue in
            localVolume = Double(newValue)
        }
    }

    // LocalizedStringResource (not String) so this actually gets looked up in the String
    // Catalog at runtime — a plain `String` return type made `Text(statusText)` use SwiftUI's
    // verbatim initializer, silently skipping localization even though the catalog had entries.
    private var statusText: LocalizedStringResource {
        if castManager.isConnected && playback.isPlaying && !playback.isBuffering {
            return "Casting to \(castManager.castDeviceName ?? "Cast device")"
        } else if playback.isBuffering {
            return "Buffering…"
        } else {
            return playback.isPlaying ? "Playing" : "Paused"
        }
    }

    @ViewBuilder
    private var artwork: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.accentColor.gradient)
            .frame(width: 220, height: 220)
            .overlay {
                if let iconURL = playback.currentStation?.iconURL {
                    AsyncImage(url: iconURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFit().padding(28)
                        } else {
                            fallbackArt
                        }
                    }
                } else {
                    fallbackArt
                }
            }
    }

    private var fallbackArt: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .padding(48)
    }

    private var castVolumeOverlay: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "tv.fill")
                Text("Volume on \(castManager.castDeviceName ?? "Cast device")")
                    .font(.footnote.weight(.medium))
                Spacer()
            }
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                Slider(value: $localVolume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
