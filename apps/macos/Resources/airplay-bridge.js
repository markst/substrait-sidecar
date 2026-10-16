// Tracks the most recently played media element in this frame and reports its
// AirPlay state to the native app.
//
// WebKit only opens the AirPlay picker from a trusted user gesture inside the page;
// script evaluated by the app does not count. So the native toolbar button first calls
// __substraitArmAirPlayPicker() in the active frame, which covers that frame's viewport
// with an invisible overlay, and then sends a real mouse click into the web view at
// __substraitFramePoint(frameId). The overlay's click handler opens the picker.
(() => {
  if (window.__substraitArmAirPlayPicker) return;
  const handler = window.webkit?.messageHandlers?.substraitAirPlay;
  if (!handler) return;
  const frameId = crypto.randomUUID ? crypto.randomUUID() : String(Math.random());
  const availability = new WeakMap();
  let active = null;

  const report = () => {
    if (!active) return;
    handler.postMessage({
      frameId,
      playing: !active.paused,
      available: availability.get(active) === true,
      wireless: active.webkitCurrentPlaybackTargetIsWireless === true,
      remoteDisabled: active.disableRemotePlayback === true,
      mse: (active.currentSrc || "").startsWith("blob:"),
    });
  };
  const watch = (el) => {
    if (availability.has(el)) return;
    availability.set(el, false);
    el.addEventListener("webkitplaybacktargetavailabilitychanged", (e) => {
      availability.set(el, e.availability === "available");
      if (el === active) report();
    });
    el.addEventListener("webkitcurrentplaybacktargetiswirelesschanged", () => { if (el === active) report(); });
  };
  const activate = (el) => { watch(el); active = el; report(); };
  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) { activate(this); return originalPlay.apply(this, args); };
  document.addEventListener("playing", (e) => { if (e.target instanceof HTMLMediaElement) activate(e.target); }, true);
  document.addEventListener("pause", (e) => { if (e.target === active) report(); }, true);

  window.__substraitArmAirPlayPicker = () => {
    if (!active) return false;
    const overlay = document.createElement("div");
    overlay.style.cssText = "position:fixed;inset:0;z-index:2147483647;background:transparent;cursor:default;";
    const disarm = () => overlay.remove();
    // WebKit anchors the picker at this click's position, which the app chooses.
    overlay.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      disarm();
      if (active) active.webkitShowPlaybackTargetPicker();
    }, true);
    // Never leave the page blocked if the native click doesn't arrive.
    setTimeout(disarm, 1000);
    (document.body || document.documentElement).appendChild(overlay);
    return true;
  };

  // Map every descendant frame to the top-level <iframe> that contains it, so the app
  // knows where to click for media playing in a (possibly cross-origin) subframe.
  const frameHosts = new Map();
  const hostIframe = (source) =>
    Array.from(document.querySelectorAll("iframe")).find((f) => f.contentWindow === source) || null;
  window.addEventListener("message", (e) => {
    const id = e.data && e.data.__substraitFrameId;
    if (typeof id !== "string") return;
    if (window !== window.top) {
      window.parent.postMessage({ __substraitFrameId: id }, "*");
      return;
    }
    const iframe = hostIframe(e.source);
    if (iframe) frameHosts.set(id, iframe);
  });
  if (window !== window.top) window.parent.postMessage({ __substraitFrameId: frameId }, "*");

  // Viewport point (CSS px, top-level frame) to click for the given frame; null if unknown.
  window.__substraitFramePoint = (id) => {
    if (id === frameId) return { x: innerWidth / 2, y: innerHeight / 2 };
    const iframe = frameHosts.get(id);
    if (!iframe || !iframe.isConnected) return null;
    const r = iframe.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return null;
    return {
      x: Math.min(Math.max(r.left + r.width / 2, 0), innerWidth - 1),
      y: Math.min(Math.max(r.top + r.height / 2, 0), innerHeight - 1),
    };
  };
})();
