# Known gaps and ideas

## Known gaps / not yet verified

- Apple Music (DRM) capture for streaming is untested.
- Only tested with a WiiM Mini. Other DLNA renderers (Sonos, hi-fi streamers, TVs) may reject a live WAV stream or need other formats.
- Occasionally the WiiM stays in "loading" after the first Play; stopping and choosing the speaker again starts it.
- Long sessions: Mac/speaker clock drift isn't compensated beyond capping the delay.
- No recovery if the default output device changes or WebKit's audio process restarts mid-stream.
- iOS AirPlay button not yet confirmed working on a device.
- Android edge-to-edge (content under the status bar) not implemented.
- Relies on private WebKit API (`_gpuProcessIdentifier`) and Substrait's current page internals; either can change without notice.

## Ideas / future work

- **Local outputs via FineTune-style routing.** Network streaming covers DLNA/UPnP renderers. Bluetooth, USB DACs and other Core Audio outputs could be reached without the network by playing the tapped audio to a user-chosen output device, the way [FineTune](https://github.com/ronitsingh10/FineTune) routes each app's process tap. FineTune is GPLv3, so either borrow ideas only or accept GPL for this project.
- Google Cast (`_googlecast._tcp`) as another network target.
- Hardening from FineTune: audio-capture permission preflight, restart capture on default-output changes, re-tap when WebKit's audio process restarts.
- Make the iOS app native Swift (drop Kotlin/Compose from iOS) to cut binary size and build time; see [design-decisions.md](design-decisions.md#kmp-on-ios-binary-size-vs-what-it-shares).
- Android streaming to network speakers via `AudioPlaybackCapture`, sharing the WAV server and DLNA control with the Mac through KMP.
- Changes that would help on Substrait's side (AirPlay-able Apple Music, Media Session, a now-playing event, stream URLs, safe-area padding) are drafted in [requests-for-substrait.md](requests-for-substrait.md).
