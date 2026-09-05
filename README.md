# Yoto-Radio

Listen to Yoto's free radio stations on iOS — no Yoto account or login required.

Yoto sells physical audio players for kids, but a chunk of their catalog — the built-in radio
stations — is served from unauthenticated, public endpoints. Yoto-Radio talks to those directly,
so you get a simple station-picker app without signing in or owning a Yoto player.

## Features

- Browse and play all free Yoto radio stations, sorted with Yoto-branded stations first, then
  stations matching your device's language, then everything else
- Background audio playback with lock-screen / Control Center now-playing controls
- AirPlay support (handled transparently by the system)
- Google Cast support, so you can stream to a Chromecast-connected speaker
- Localized in English and French

## How it works

The app calls the public parts of `api.yotoplay.com`:

- `GET /card/library/free` — lists free cards, filtered down to `metadata.category == "radio"`
- `GET /card/{cardId}` — resolves each card's chapters/tracks to their stream URLs

No API key or authenticated session is needed for either endpoint.

## Requirements

- Xcode with an iOS 27.0+ SDK
- iOS 27.0+ device or simulator

## Building

Open `Yoto.xcodeproj` in Xcode and run the `Yoto` scheme. The project depends on the
[google-cast-sdk](https://github.com/SRGSSR/google-cast-sdk) Swift package for Cast support,
resolved automatically by Xcode on first build.

## Project layout

- `Yoto/Models` — `RadioStation` and the API's wire types
- `Yoto/Networking` — `YotoAPIClient` (fetches and resolves stations) and `RadioStore`
- `Yoto/Playback` — `PlaybackManager` (local `AVPlayer` playback) and `CastManager` (Google Cast
  session lifecycle)
- `Yoto/Views` — station grid, now-playing banner/sheet, AirPlay and Cast controls
