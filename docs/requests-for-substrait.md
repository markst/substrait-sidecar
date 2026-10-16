# Requests for the Substrait team

Hi! I've been building [Substrait Sidecar](../README.md), an unofficial personal wrapper that plays Substrait in its own Mac/iOS/Android app so its audio can go to a network speaker without sending the rest of my Mac's audio there. While building it I hit a few things where small changes on your side would help — several of them also help regular Safari users. In priority order:

## 1. Let Apple Music AirPlay in Safari

When `armAppleMsePath` arms the ManagedMediaSource path it sets `disableRemotePlayback = true` on `#apple-music-player`. WebKit requires that for `ManagedMediaSource` unless an AirPlay-compatible alternative is offered, so Safari's AirPlay can't play Apple Music — for every Safari user, not just wrappers. (We currently work around it by hiding `window.ManagedMediaSource` before your scripts run, which will break if that code changes.)

Options, best first:

- Offer an AirPlay alternative alongside the MSE source, as WebKit intends:

  ```js
  const audio = document.getElementById("apple-music-player");
  const mms = new ManagedMediaSource();
  audio.disableRemotePlayback = false;
  audio.innerHTML = "";
  const mse = document.createElement("source");
  mse.src = URL.createObjectURL(mms);
  mse.type = "audio/mp4";
  const airplay = document.createElement("source");
  airplay.src = hlsManifestUrl;              // the native HLS URL MusicKit already uses
  airplay.type = "application/x-mpegURL";
  audio.append(mse, airplay);
  ```

- Or skip the MSE path when AirPlay matters — at minimum inside the wrapper:

  ```js
  const inSidecar = !!window.webkit?.messageHandlers?.substraitAirPlay;
  if (!inSidecar) armAppleMsePath(enabled);
  ```

## 2. Media Session metadata and actions

Setting `navigator.mediaSession` gives Safari (and WKWebView apps) Now Playing, media keys and lock-screen controls, and lets the wrapper send real track info to the speaker (today a WiiM just shows "Substrait").

```js
navigator.mediaSession.metadata = new MediaMetadata({
  title, artist, album,
  artwork: [{ src: artworkUrl, sizes: "512x512", type: "image/jpeg" }],
});
navigator.mediaSession.setActionHandler("play", () => player.play());
navigator.mediaSession.setActionHandler("pause", () => player.pause());
navigator.mediaSession.setActionHandler("nexttrack", () => queue.next());
navigator.mediaSession.setActionHandler("previoustrack", () => queue.previous());
navigator.mediaSession.playbackState = isPlaying ? "playing" : "paused";
```

## 3. A small "now playing" event

A stable event would let the wrapper keep the speaker in step (pause/resume, source changes) without depending on your internals:

```js
window.dispatchEvent(new CustomEvent("substrait:nowplaying", {
  detail: {
    state: "playing",            // "playing" | "paused" | "stopped"
    source: "bandcamp",          // apple | tidal | youtube | bandcamp | radio | …
    title, artist, artwork,
    streamUrl,                   // see 4; omit for DRM sources
  },
}));
```

## 4. Include `streamUrl` for unprotected sources

Radio and Bandcamp items already carry `stream_url`. If the event above includes it, the wrapper can hand that URL straight to the speaker (DLNA/AirPlay): original quality, no capture, no ~2 s delay. Audio capture stays as the fallback for Apple Music, TIDAL and YouTube.

## 5. Safe-area padding for scrolling content

With `viewport-fit=cover`, the fixed header pads for `env(safe-area-inset-top)` but the scrolling content starts at the very top, under the notch/status bar (visible in the standalone PWA and in WebView wrappers):

```css
.scroll-container {
  padding-top: calc(env(safe-area-inset-top) + var(--header-height));
}
```

## 6. A visible back button on inner pages

In the installed PWA (standalone mode) there's no browser back button, and on iOS the only way back is an edge swipe that isn't discoverable. Wrappers have the same problem. A back affordance in the header on non-top-level pages (calling `router.back()`, or linking to the parent screen when there's no history) would fix it for both.

## FYI (no action needed)

- Substrait plays fine in `WKWebView` with a Safari user agent and in Android WebView once protected media is granted.
- YouTube/SoundCloud/Bandcamp embeds can't AirPlay from Safari either; that's down to those providers.

Thanks — happy to test anything.
