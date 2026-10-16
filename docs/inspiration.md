# Inspiration and prior art

- [FineTune](https://github.com/ronitsingh10/FineTune) — open-source per-app volume/routing app built on Core Audio process taps. Confirmed the tap + private aggregate device approach and is the reference for the hardening ideas in [roadmap.md](roadmap.md) (orphaned tap cleanup, permission preflight, device and process monitors). GPLv3; ideas only, no code copied.
- Apple's ["Capturing system audio with Core Audio taps"](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) documentation and the `CATapDescription` / `AudioHardwareCreateProcessTap` headers in the macOS SDK — the basis of `AppAudioCapture`.
- Rogue Amoeba's [Airfoil](https://rogueamoeba.com/airfoil/) and [SoundSource](https://rogueamoeba.com/soundsource/) — the commercial "send one app's audio to a speaker" tools this project is a small, single-purpose take on. Using Airfoil with a dedicated browser was the off-the-shelf alternative considered first.
- [nriley/SoundSource](https://github.com/nriley/SoundSource) — an old open-source SoundSource 2.5 with a CLI; looked at, but it only switches the system-wide output device, which is exactly what this project avoids.
- The "capture, serve over HTTP, tell the renderer to play the URL" pattern used by casting tools such as mkchromecast, applied here to DLNA/UPnP.
