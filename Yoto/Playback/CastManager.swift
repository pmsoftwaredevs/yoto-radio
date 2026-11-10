//
//  CastManager.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import Combine
import Foundation

/// What the Cast receiver reports it is doing right now.
struct CastRemoteSnapshot {
    var contentURL: URL?
    var isPlaying: Bool
    var isBuffering: Bool
    var isIdle: Bool
}

#if canImport(GoogleCast)
import GoogleCast

/// Wraps the Google Cast session lifecycle and remote media control.
/// Targets the Default Media Receiver (kGCKDefaultMediaReceiverApplicationID) so no
/// custom receiver app registration is needed for a generic audio stream URL.
@MainActor
final class CastManager: NSObject, ObservableObject {
    static let shared = CastManager()

    @Published private(set) var isConnected = false
    @Published private(set) var castDeviceName: String?
    @Published private(set) var streamVolume: Float = 1.0

    /// Fired when a Cast session connects/reconnects or drops, so PlaybackManager can
    /// hand playback off to/from the receiver without the two types depending on Combine.
    var onSessionStarted: (() -> Void)?
    /// Fired when an existing session is re-attached (e.g. the app returns from background).
    /// The receiver may already be playing, so callers should sync state, not reload media.
    var onSessionResumed: (() -> Void)?
    var onSessionEnded: (() -> Void)?
    /// Fired whenever the receiver's player state changes: (isPlaying, isBuffering).
    var onRemoteStateChanged: ((Bool, Bool) -> Void)?

    private override init() {
        super.init()
    }

    /// Call once, early in app launch, before any other GoogleCast API use.
    func configure() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().sessionManager.add(self)
    }

    func load(_ station: RadioStation) {
        guard let client = currentSession?.remoteMediaClient else { return }

        let metadata = GCKMediaMetadata(metadataType: .musicTrack)
        metadata.setString(station.title, forKey: kGCKMetadataKeyTitle)
        if let iconURL = station.iconURL {
            metadata.addImage(GCKImage(url: iconURL, width: 200, height: 200))
        }

        let infoBuilder = GCKMediaInformationBuilder(contentURL: station.streamURL)
        infoBuilder.streamType = .live
        infoBuilder.contentType = station.format?.lowercased() == "mp3" ? "audio/mpeg" : "audio/aac"
        infoBuilder.metadata = metadata

        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.mediaInformation = infoBuilder.build()
        requestBuilder.autoplay = true

        let request = client.loadMedia(with: requestBuilder.build())
        isLoading = true
        let delegate = LoadRequestDelegate { [weak self] succeeded in
            guard let self else { return }
            self.isLoading = false
            self.loadDelegate = nil
            if succeeded, let state = self.remoteState {
                self.onRemoteStateChanged?(state.isPlaying, state.isBuffering)
            } else if !succeeded {
                self.onRemoteStateChanged?(false, false)
            }
        }
        loadDelegate = delegate
        request.delegate = delegate
    }

    /// True between asking the receiver to load a station and it answering; status updates in
    /// that window can still describe the previous (idle/other) media.
    private(set) var isLoading = false
    private var loadDelegate: LoadRequestDelegate?

    func pause() {
        currentSession?.remoteMediaClient?.pause()
    }

    func resume() {
        currentSession?.remoteMediaClient?.play()
    }

    func stop() {
        currentSession?.remoteMediaClient?.stop()
    }

    func setVolume(_ volume: Float) {
        streamVolume = volume
        currentSession?.remoteMediaClient?.setStreamVolume(volume, customData: nil)
    }

    func endSession() {
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
    }

    /// The station URL the receiver currently has loaded, if any.
    var remoteContentURL: URL? {
        currentSession?.remoteMediaClient?.mediaStatus?.mediaInformation?.contentURL
    }

    /// Receiver playback state, or nil when no status is available yet.
    var remoteState: (isPlaying: Bool, isBuffering: Bool, isIdle: Bool)? {
        guard let status = currentSession?.remoteMediaClient?.mediaStatus else { return nil }
        return Self.map(status.playerState)
    }

    /// Asks the receiver for its current media status and waits (briefly) for the answer.
    /// Returns nil when the receiver has no media session at all (idle, or claimed by another
    /// sender that stopped/replaced it).
    func refreshRemoteSnapshot() async -> CastRemoteSnapshot? {
        if let client = currentSession?.remoteMediaClient {
            let waiter = StatusRequestWaiter()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiter.continuation = continuation
                let request = client.requestStatus()
                request.delegate = waiter
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    waiter.finish()
                }
            }
        }
        guard let status = currentSession?.remoteMediaClient?.mediaStatus else { return nil }
        let state = Self.map(status.playerState)
        return CastRemoteSnapshot(
            contentURL: status.mediaInformation?.contentURL,
            isPlaying: state.isPlaying,
            isBuffering: state.isBuffering,
            isIdle: status.playerState == .idle
        )
    }

    private static func map(_ state: GCKMediaPlayerState) -> (isPlaying: Bool, isBuffering: Bool, isIdle: Bool) {
        switch state {
        case .playing: return (true, false, false)
        case .buffering, .loading: return (true, true, false)
        case .idle: return (false, false, true)
        default: return (false, false, false)
        }
    }

    private func attachClientListener(_ session: GCKCastSession) {
        session.remoteMediaClient?.remove(self)
        session.remoteMediaClient?.add(self)
    }

    private var currentSession: GCKCastSession? {
        GCKCastContext.sharedInstance().sessionManager.currentCastSession
    }
}

/// Reports the outcome of a load request.
private final class LoadRequestDelegate: NSObject, GCKRequestDelegate {
    private let completion: (Bool) -> Void
    init(completion: @escaping (Bool) -> Void) { self.completion = completion }

    func requestDidComplete(_ request: GCKRequest) { completion(true) }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) { completion(false) }
    func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) { completion(false) }
}

/// Bridges GCKRequest's delegate callbacks to a one-shot continuation.
private final class StatusRequestWaiter: NSObject, GCKRequestDelegate {
    var continuation: CheckedContinuation<Void, Never>?

    func finish() {
        continuation?.resume()
        continuation = nil
    }

    func requestDidComplete(_ request: GCKRequest) { finish() }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) { finish() }
    func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) { finish() }
}

extension CastManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        isConnected = true
        castDeviceName = session.device.friendlyName
        streamVolume = session.currentDeviceVolume
        attachClientListener(session)
        onSessionStarted?()
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
        isConnected = true
        castDeviceName = session.device.friendlyName
        streamVolume = session.currentDeviceVolume
        attachClientListener(session)
        onSessionResumed?()
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        isConnected = false
        castDeviceName = nil
        onSessionEnded?()
    }
}

extension CastManager: GCKRemoteMediaClientListener {
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        guard let mediaStatus else { return }
        let state = Self.map(mediaStatus.playerState)
        onRemoteStateChanged?(state.isPlaying, state.isBuffering)
    }
}

#else

/// GoogleCast package not added to the project yet — see setup steps.
/// Everything below compiles to a harmless no-op stub so the rest of the app builds and runs;
/// once the SPM package is added this file's `#if canImport(GoogleCast)` branch activates instead.
@MainActor
final class CastManager: NSObject, ObservableObject {
    static let shared = CastManager()

    @Published private(set) var isConnected = false
    @Published private(set) var castDeviceName: String?
    @Published private(set) var streamVolume: Float = 1.0

    var onSessionStarted: (() -> Void)?
    var onSessionResumed: (() -> Void)?
    var onSessionEnded: (() -> Void)?
    var onRemoteStateChanged: ((Bool, Bool) -> Void)?
    var isLoading: Bool { false }
    var remoteContentURL: URL? { nil }
    var remoteState: (isPlaying: Bool, isBuffering: Bool, isIdle: Bool)? { nil }

    func refreshRemoteSnapshot() async -> CastRemoteSnapshot? { nil }
    func configure() {}
    func load(_ station: RadioStation) {}
    func pause() {}
    func resume() {}
    func stop() {}
    func setVolume(_ volume: Float) { streamVolume = volume }
    func endSession() {}
}

#endif
