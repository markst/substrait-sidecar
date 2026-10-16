# Design decisions

How the project got to its current shape, and why.

## Wrap the web player instead of re-implementing it

Substrait aggregates many sources (Apple Music via MusicKit JS, TIDAL, YouTube, Bandcamp, SoundCloud, Mixcloud, Deezer, radio) and handles their auth server-side. Re-implementing playback natively isn't realistic, so every app hosts the real site in the platform web view (`WKWebView`, Android `WebView`). Sign-in is email + typed code, so no deep-link handling is needed.

## Why the Mac app is native Swift, not Compose

Android and iOS share a Kotlin Multiplatform / Compose Multiplatform UI (`shared/`). Compose Desktop runs on the JVM and can only embed Chromium (KCEF), which has neither WebKit's per-element AirPlay nor a process we can tap cleanly. The Mac app is therefore a standalone SwiftUI/AppKit project around `WKWebView`.

The streaming pieces (renderer discovery, AVTransport control, WAV server) could move to KMP later — worthwhile if Android also streams to speakers. The real-time capture callback should stay native: Kotlin/Native's GC and allocation can glitch a real-time audio thread.

## Routing only this app's audio on macOS

| Option | Outcome |
|---|---|
| System AirPlay output | Rejected: sends everything on the Mac to the speaker. |
| Set the app's output device to an AirPlay device | Not possible: AirPlay receivers only appear as Core Audio devices once selected as the *system* output. |
| Virtual audio driver (BlackHole-style) | Rejected: system-wide install, and WebKit audio can't be pointed at it per app. |
| WebKit per-element AirPlay | Kept (AirPlay button): Apple-quality and low delay, but blocked for MSE sources such as YouTube. |
| Core Audio process tap of our own audio + network stream | Kept (stream button): works for every source. |

## Network protocol for the stream

- Plain HTTP live WAV rather than AAC/MP3: no encoder, lossless, trivial on a LAN, and accepted by the WiiM as a live stream.
- Started with WiiM's LinkPlay HTTP API (proven quickly), then moved to standard DLNA/UPnP `AVTransport` so non-WiiM renderers can work. Google Cast and a native AirPlay (RAOP) sender were considered; both are more work and are listed in [roadmap.md](roadmap.md).

## Personal-use trade-offs

The Mac app is unsandboxed, ad-hoc signed and uses private WebKit API (`_gpuProcessIdentifier`). That's acceptable for a personal sandbox, not for App Store distribution.

## KMP on iOS: binary size vs. what it shares

On iOS the shared Kotlin code is tiny: a Compose screen hosting one `WKWebView`, plus a few delegates. Everything iOS-specific (navigation bar, AirPlay button, audio session) is already SwiftUI. Yet the app ships the whole Kotlin/Native runtime and Compose Multiplatform (Skia-based rendering) to draw that one web view.

Measured locally (Debug, simulator): the app bundle is about 40 MB, and the static `Shared.framework` it links is about 243 MB before linking. Release builds strip and dead-code-eliminate a lot, but Compose Multiplatform on iOS typically still adds tens of MB, plus Kotlin/Native build time on every Xcode build. (Release size not measured yet.)

That cost buys little: Android and iOS share almost no logic, only a URL constant and the link-scheme allow-list. A plain SwiftUI app with a `UIViewRepresentable` `WKWebView` would do the same job with a much smaller binary and no Gradle step in the Xcode build. Moving to it would mean:

- Port `SubstraitWebView`, `NavigationDelegate` and `PopupDelegate` from `shared/src/iosMain` to Swift (largely mechanical).
- Drop `ComposeView`, `SubstraitWebViewRegistry` and the "Compile Kotlin Framework" build phase; `WebNavigation` observes the web view directly.
- Remove the iOS targets from `shared/build.gradle.kts`, leaving KMP for Android only (or plain Android).

KMP would earn its keep again if real logic were shared, e.g. Android speaker streaming reusing the DLNA control and WAV server (see [roadmap.md](roadmap.md)) — and even then the iOS app could keep a native UI and only link a small non-Compose module.
