# macOS app

Native SwiftUI/AppKit app (xcodegen project in `apps/macos/`) hosting Substrait in a `WKWebView`. It has two toolbar buttons for getting audio to a speaker: **AirPlay** (per media element) and **Stream** (capture the app's audio and send it to a network speaker).

## Layout (`apps/macos/Sources`)

| Directory | Layer |
|---|---|
| `App/` | App entry, SwiftUI window and toolbar (`ContentView`), `WebViewHost` |
| `Player/` | `WebPlayer` (the Substrait `WKWebView`, script injection, AirPlay picker) and `AirPlayState` |
| `Streaming/` | `SpeakerStreamer`: coordinates capture → server → speaker |
| `Streaming/Capture/` | Core Audio process tap of the app's own audio |
| `Streaming/Server/` | Ring buffer and live WAV HTTP server |
| `Speakers/` | DLNA/UPnP renderer discovery (SSDP) and AVTransport control |

Injected page scripts (`airplay-bridge.js`, `disable-mse.js`) and the app icon live in `apps/macos/Resources/`. `Sources/` is an Xcode 16 synchronized folder (`type: syncedFolder` in `project.yml`), so new files there are built without regenerating the project.

## 1. AirPlay (per media element)

Uses WebKit's built-in AirPlay for a single `<audio>`/`<video>` element (`allowsAirPlayForMediaPlayback`), so only that element's audio is routed and the system output is untouched. Works with any AirPlay receiver.

- `airplay-bridge.js` is injected into every frame. It tracks the element that is playing and reports its AirPlay availability to native code, tagged with a per-frame id.
- `webkitShowPlaybackTargetPicker()` is ignored unless called during a trusted user gesture *inside the page*. `evaluateJavaScript`, and even WebKit's private force-user-gesture evaluation, don't count; a synthetic `NSEvent` click sent through the window does. So the toolbar button arms a full-viewport transparent overlay in the playing frame and clicks it, and the overlay opens the picker. Cross-origin subframes are located by postMessage-ing frame ids up to the top frame.
- WebKit anchors the picker at the click point but mirrors it vertically within the view. The click is therefore placed near the bottom edge (`WebPlayer.viewportPointBelowPointer`) so the picker hangs under the toolbar button, 40 pt clear of the edges, because a mouse-down in the window's resize margin starts a live resize and swallows the click.
- `disable-mse.js` hides `window.ManagedMediaSource` at document start. Substrait's Apple Music MSE path sets `disableRemotePlayback` (blocking AirPlay); without `ManagedMediaSource` the site falls back to native HLS, which AirPlay can play.
- Limitation: sources that stream via Media Source Extensions (e.g. YouTube) or disable remote playback can't use this path.

These findings came from instrumented test harnesses (WebKit unified logs, `CGWindowList` checks for the picker window).

## 2. Stream to a network speaker (capture app audio)

Works for every source, including YouTube, and with DLNA/UPnP media renderers (tested with a WiiM Mini).

### Capture (`Streaming/Capture/AppAudioCapture.swift`)

- WKWebView media plays in a per-app `com.apple.WebKit.GPU` process, not in the app process; Safari and other apps have their own. `WKWebView._gpuProcessIdentifier` (private) gives our PID, which `kAudioHardwarePropertyTranslatePIDToProcessObject` turns into a Core Audio process object.
- `CATapDescription(stereoMixdownOfProcesses:)` (macOS 14.2+) with `muteBehavior = .muted` and `isPrivate = true`, attached to a private aggregate device clocked by the default output. Only this app's audio is captured, and it's muted on the Mac. Private objects are torn down by Core Audio if the app dies, so a crash shouldn't leave anything muted.
- The IO proc converts float to interleaved Int16 into a preallocated buffer and writes into a lock-protected byte ring (`LiveAudioBuffer`), so the real-time thread never allocates. Verified with a 440 Hz oscillator: captured at 440.0 Hz at the expected level.

### Serve (`Streaming/Server/`)

- Uncompressed 16-bit stereo WAV at the tap's rate (48 kHz) with "unknown length" RIFF sizes, plus DLNA streaming headers. No encoder, lossless, about 1.5 Mbit/s — fine on a LAN. The WiiM's FFmpeg-based player (`Lavf`) accepts it as a live stream.
- Latency control: each listener starts 0.25 s behind live, is skipped forward if it falls more than 1.5 s behind, and the server stops sending while more than 1 s of data is unacknowledged, so a slow consumer can't grow the delay indefinitely.

### Play (`Speakers/`, `Streaming/SpeakerStreamer.swift`)

- SSDP `M-SEARCH` for `AVTransport:1` services over plain BSD sockets (`SSDPDiscovery`; no multicast entitlement needed on macOS), device description parsing for name and control URL (`MediaRendererBrowser`, refreshed every 30 s).
- SOAP `SetAVTransportURI` (DIDL-Lite metadata, `protocolInfo="http-get:*:audio/wav:*"`) + `Play`; `Stop` on stop (`AVTransport`). Stopping stops the renderer first, then un-mutes the Mac.
- History: the first version used WiiM's LinkPlay HTTP API (`setPlayerCmd:play:<url>`); it was replaced by standard DLNA/UPnP so other renderers can work, and the WiiM keeps working.

Expect ~1.5–2 s of delay on play/pause/seek. On WiiM, speakers grouped with the target in the WiiM app play along.

## Permissions

On first use the app may ask for **Local Network** (speaker discovery and streaming) and **System Audio Recording** (process tap). The app is unsandboxed and ad-hoc signed for personal use.
