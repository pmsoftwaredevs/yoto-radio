//
//  CastManager.swift
//  Yoto
//
//  Created by user on 05/09/2026.
//

import Combine
import Foundation

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
    var onSessionEnded: (() -> Void)?

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

        client.loadMedia(with: requestBuilder.build())
    }

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

    private var currentSession: GCKCastSession? {
        GCKCastContext.sharedInstance().sessionManager.currentCastSession
    }
}

extension CastManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        isConnected = true
        castDeviceName = session.device.friendlyName
        streamVolume = session.currentDeviceVolume
        onSessionStarted?()
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
        isConnected = true
        castDeviceName = session.device.friendlyName
        streamVolume = session.currentDeviceVolume
        onSessionStarted?()
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        isConnected = false
        castDeviceName = nil
        onSessionEnded?()
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
    var onSessionEnded: (() -> Void)?

    func configure() {}
    func load(_ station: RadioStation) {}
    func pause() {}
    func resume() {}
    func stop() {}
    func setVolume(_ volume: Float) { streamVolume = volume }
    func endSession() {}
}

#endif
