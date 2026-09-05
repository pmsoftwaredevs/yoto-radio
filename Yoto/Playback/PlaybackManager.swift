//
//  PlaybackManager.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import AVFoundation
import Combine
import Foundation

/// Owns "what's playing right now" for the whole app: either a local AVPlayer (which also
/// covers AirPlay — the system routes that transparently) or, once a Cast session is active,
/// the connected Google Cast receiver via CastManager.
@MainActor
final class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()

    @Published private(set) var currentStation: RadioStation?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false

    let castManager = CastManager.shared

    private var player: AVPlayer?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    var isCasting: Bool { castManager.isConnected }

    private init() {
        configureAudioSession()
        castManager.onSessionStarted = { [weak self] in self?.handleCastSessionStarted() }
        castManager.onSessionEnded = { [weak self] in self?.handleCastSessionEnded() }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        // Activating synchronously on the main thread risks a UI hang; use the async variant.
        session.activate(options: []) { _, _ in }
    }

    func play(_ station: RadioStation) {
        currentStation = station
        if isCasting {
            player?.pause()
            player = nil
            castManager.load(station)
            isPlaying = true
            isBuffering = false
        } else {
            playLocally(station)
        }
    }

    func togglePlayPause() {
        guard currentStation != nil else { return }
        if isCasting {
            if isPlaying {
                castManager.pause()
            } else {
                castManager.resume()
            }
            isPlaying.toggle()
        } else {
            if isPlaying {
                player?.pause()
                isPlaying = false
            } else {
                player?.play()
                isPlaying = true
            }
        }
    }

    func stop() {
        player?.pause()
        player = nil
        statusObserver = nil
        rateObserver = nil
        castManager.stop()
        isPlaying = false
        isBuffering = false
        currentStation = nil
    }

    private func playLocally(_ station: RadioStation) {
        statusObserver = nil
        rateObserver = nil

        let item = AVPlayerItem(url: station.streamURL)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        isBuffering = true
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                self?.isBuffering = status != .readyToPlay
            }
        }
        rateObserver = newPlayer.observe(\.rate, options: [.new]) { [weak self] observedPlayer, _ in
            let rate = observedPlayer.rate
            Task { @MainActor [weak self] in
                self?.isPlaying = rate > 0
            }
        }

        newPlayer.play()
        isPlaying = true
    }

    private func handleCastSessionStarted() {
        guard let station = currentStation else { return }
        player?.pause()
        player = nil
        castManager.load(station)
        isPlaying = true
        isBuffering = false
    }

    private func handleCastSessionEnded() {
        guard let station = currentStation else { return }
        playLocally(station)
    }
}
