<p align="center">
  <img src="docs/images/app-icon.png" alt="Substrait Sidecar app icon" width="128" height="128">
</p>

<h1 align="center">Substrait Sidecar</h1>

<p align="center">
  Unofficial companion apps for the <a href="https://substra.it">Substrait</a> web player on <b>macOS</b>, <b>iOS</b> and <b>Android</b>.<br>
  <sub>Not affiliated with Substrait.</sub>
</p>

<p align="center">
  <a href="https://github.com/markst/substrait-sidecar/releases/latest"><img src="https://img.shields.io/github/v/release/markst/substrait-sidecar?label=Download%20for%20macOS&logo=apple&color=4B2928" alt="Download the latest macOS release"></a>
</p>

> **Sandbox / work in progress.** This repo is a place to experiment. Nothing here is fully tested, APIs used on the Mac include private WebKit calls, and things will break. The macOS download is ad-hoc signed and not notarized, so macOS asks you to approve it once — see the [release notes](https://github.com/markst/substrait-sidecar/releases/latest).

## Why this exists

I really wanted to use Substrait, but I don't like listening through a browser tab: I need my Mac's audio for other things (calls, videos, notifications) while the music plays on the speaker.

macOS can AirPlay the entire system output, but then everything goes to the speaker. Substrait Sidecar gives Substrait its own app whose audio — and only its audio — can go to a network speaker (in my case a WiiM), while the rest of the Mac keeps playing locally.

On the Mac that works two ways:

- **AirPlay** a single media element via WebKit (low delay; not for YouTube-style MSE streams).
- **Stream** the app's own audio, captured with a Core Audio process tap, to any DLNA/UPnP speaker (works for every source, ~1.5–2 s delay).

<p align="center">
  <img src="https://github.com/user-attachments/assets/b63e040a-4c28-4e7d-839d-94252a188623" alt="Substrait Sidecar on macOS: the Substrait web player in its own window, with AirPlay and speaker-streaming buttons in the toolbar" width="800">
  <br>
  <sub>The macOS app: Substrait in its own window, with AirPlay and speaker streaming in the toolbar.</sub>
</p>

## What's in the repo

| Path | What it is |
|---|---|
| `apps/macos/` | Native Swift/SwiftUI Mac app (xcodegen) hosting Substrait in a `WKWebView`, with AirPlay and speaker streaming. |
| `shared/` | Kotlin Multiplatform + Compose Multiplatform UI for Android and iOS, wrapping the platform web view. |
| `apps/android/` | Android entry point (Gradle module `:androidApp`, AGP 9 layout). |
| `apps/ios/` | iOS Xcode project: SwiftUI shell hosting the Compose UI plus a native AirPlay button. |
| `docs/` | Technical documentation (below). |

Identifiers: `dev.markturnip.substrait` (Android, iOS), `dev.markturnip.substrait.mac` (macOS).

## Building

Prerequisites: Xcode 26+, `xcodegen`, JDK 17+, Android SDK.

```sh
# macOS
cd apps/macos && xcodegen generate && xcodebuild -project SubstraitMac.xcodeproj -scheme SubstraitMac build

# Android
./gradlew :androidApp:assembleDebug

# iOS (or open apps/ios/iosApp.xcodeproj in Xcode and run on a device)
xcodebuild -project apps/ios/iosApp.xcodeproj -scheme iosApp -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Docs

- [macOS app](docs/macos.md) — source layout, WebKit AirPlay workarounds, process-tap capture, WAV server, DLNA control.
- [iOS and Android](docs/mobile.md) — web view hosting, AirPlay on iOS, safe areas, Android WebView quirks.
- [iOS navigation](docs/ios-navigation.md) — why there is a native back bar, and the approaches considered.
- [Design decisions](docs/design-decisions.md) — why a wrapper, why native Swift on the Mac, routing options considered.
- [Known gaps and ideas](docs/roadmap.md) — what's untested and what could come next.
- [Inspiration and prior art](docs/inspiration.md) — FineTune, Apple's Core Audio taps docs, Rogue Amoeba.
- [Requests for Substrait](docs/requests-for-substrait.md) — site changes that would help (AirPlay-able Apple Music, Media Session, a now-playing event).
