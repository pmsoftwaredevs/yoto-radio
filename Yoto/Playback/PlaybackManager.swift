//
//  PlaybackManager.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

/// Receives ICY/ID3 timed metadata (the "StreamTitle" a radio station sends for the current
/// song) from the AVPlayerItem and forwards the parsed title.
private final class StreamMetadataReceiver: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var onTitle: (@Sendable (String) -> Void)?

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        let titleItems = groups.flatMap(\.items).filter {
            $0.identifier == .icyMetadataStreamTitle
                || $0.identifier == .commonIdentifierTitle
                || $0.identifier == .id3MetadataTitleDescription
        }
        let onTitle = onTitle
        Task {
            for item in titleItems {
                guard let raw = try? await item.load(.stringValue) else { continue }
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                onTitle?(value)
                return
            }
        }
    }
}

/// Owns "what's playing right now" for the whole app: either a local AVPlayer (which also
/// covers AirPlay — the system routes that transparently) or, once a Cast session is active,
/// the connected Google Cast receiver via CastManager.
@MainActor
final class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()

    @Published private(set) var currentStation: RadioStation?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    /// Song currently airing on the station, from in-stream ICY metadata. Nil when the
    /// station doesn't publish any (or hasn't yet since tuning in).
    @Published private(set) var trackTitle: String?
    @Published private(set) var trackArtist: String?

    let castManager = CastManager.shared

    var trackSummary: String? {
        guard let trackTitle else { return nil }
        return trackArtist.map { "\($0) – \(trackTitle)" } ?? trackTitle
    }

    private var player: AVPlayer?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private let metadataReceiver = StreamMetadataReceiver()
    private var queue: [RadioStation] = []
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    var isCasting: Bool { castManager.isConnected }

    private init() {
        configureAudioSession()
        castManager.onSessionStarted = { [weak self] in self?.handleCastSessionStarted() }
        castManager.onSessionEnded = { [weak self] in self?.handleCastSessionEnded() }
        metadataReceiver.onTitle = { [weak self] raw in
            Task { @MainActor [weak self] in self?.handleStreamTitle(raw) }
        }
        configureRemoteCommands()
    }

    // MARK: - System controls (lock screen, Control Center, CarPlay/car stereo, headphones)

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resumeIfPaused() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pauseIfPlaying() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNextStation() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPreviousStation() }
            return .success
        }
        // Live streams can't seek or skip within the stream.
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    func playNextStation() { stepStation(by: 1) }
    func playPreviousStation() { stepStation(by: -1) }

    private func stepStation(by offset: Int) {
        guard let current = currentStation, !queue.isEmpty,
              let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        let next = (index + offset + queue.count) % queue.count
        play(queue[next])
    }

    private func resumeIfPaused() {
        if !isPlaying { togglePlayPause() }
    }

    private func pauseIfPlaying() {
        if isPlaying { togglePlayPause() }
    }

    private func handleStreamTitle(_ raw: String) {
        // Stations conventionally send "Artist - Title".
        if let range = raw.range(of: " - ") {
            trackArtist = String(raw[..<range.lowerBound])
            trackTitle = String(raw[range.upperBound...])
        } else {
            trackArtist = nil
            trackTitle = raw
        }
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let station = currentStation else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }

        var info: [String: Any] = [
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyAlbumTitle: station.title,
        ]
        // Pseudo-track: current song if the stream tells us, else the station itself.
        if let trackTitle {
            info[MPMediaItemPropertyTitle] = trackTitle
            info[MPMediaItemPropertyArtist] = trackArtist ?? station.title
        } else {
            info[MPMediaItemPropertyTitle] = station.title
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork(for station: RadioStation) {
        artworkTask?.cancel()
        artwork = nil
        guard let url = station.iconURL else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), !Task.isCancelled else { return }
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self?.artwork = art
            self?.updateNowPlayingInfo()
        }
    }

    private func resetTrackMetadata() {
        trackTitle = nil
        trackArtist = nil
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        // Activating synchronously on the main thread risks a UI hang; use the async variant
        // where available and fall back to activating off the main thread on older OS versions.
        if #available(iOS 27.0, *) {
            session.activate(options: []) { _, _ in }
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                try? session.setActive(true)
            }
        }
    }

    func play(_ station: RadioStation, in stations: [RadioStation]? = nil) {
        if let stations { queue = stations }
        if currentStation?.id != station.id { resetTrackMetadata() }
        currentStation = station
        loadArtwork(for: station)
        if isCasting {
            player?.pause()
            player = nil
            castManager.load(station)
            isPlaying = true
            isBuffering = false
        } else {
            playLocally(station)
        }
        updateNowPlayingInfo()
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
        updateNowPlayingInfo()
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
        artworkTask?.cancel()
        artwork = nil
        resetTrackMetadata()
        updateNowPlayingInfo()
    }

    private func playLocally(_ station: RadioStation) {
        statusObserver = nil
        rateObserver = nil

        let item = AVPlayerItem(url: station.streamURL)
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(metadataReceiver, queue: .main)
        item.add(metadataOutput)
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
                self?.updateNowPlayingInfo()
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
