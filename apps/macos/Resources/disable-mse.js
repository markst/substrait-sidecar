// Hides ManagedMediaSource so Substrait's armAppleMsePath does not force
// disableRemotePlayback on #apple-music-player (which blocks AirPlay).
(() => {
  try {
    Object.defineProperty(window, "ManagedMediaSource", { value: undefined, configurable: true, writable: false });
  } catch (_) {}
})();
