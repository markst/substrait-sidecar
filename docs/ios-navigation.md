# iOS navigation

## Problem

Substrait is a Next.js single-page app: moving between screens changes the URL with `history.pushState` instead of loading a new page. In the iOS app the only way back is WebKit's swipe-back gesture (`allowsBackForwardNavigationGestures`). There's no visible back button and no title, so it isn't obvious you can go back or where you are. (Android is fine: the system back gesture/button calls `WebView.goBack()`.)

Substrait's own installed PWA has the same gap — standalone mode has no browser chrome — see [requests-for-substrait.md](requests-for-substrait.md).

## Approaches considered

### A. A new web view per screen on a native navigation stack (Hotwire/Turbo Native style)

Inject a script that intercepts in-app navigation (link clicks, `history.pushState`), cancel it, post the URL to native, and push a `UIViewController` with a fresh `WKWebView` for that URL; back pops it. (`WKNavigationDelegate` isn't called for same-document `pushState` navigations, so the script is required.)

Rejected for now:

- **Playback breaks.** The player (MusicKit `<audio>`, YouTube iframes, queue) lives in the page's JavaScript. Audio started in a pushed web view stops when it's popped, and every pushed screen carries its own copy of the player.
- **Slow.** Each push is a full Next.js page load and hydration instead of an instant client-side transition.
- **State is lost** between web views (scroll, filters, in-memory data).
- **Fragile.** Depends on Substrait's internal routing; a site update can break interception.

A hidden "player" web view plus content-only pushed views would need the site to be built for it.

### B. One web view plus a native navigation bar (implemented)

Keep the single web view, so playback is untouched, and add native chrome around it:

- A top bar with a **back button** shown when `webView.canGoBack` and the page isn't a top-level screen; tapping it calls `goBack()`. WebKit records same-document `pushState` navigations in its back/forward list and updates `canGoBack`/`url` via KVO.
- A **title** from `webView.title` (`document.title`, minus the "Substrait" suffix).
- **Top-level screens** (Substrait's main tabs) hide the back button, like a tab-bar app.
- The **AirPlay** button sits in the same bar; swipe-back keeps working.

### C. B plus simulated push/pop transitions

On forward navigation, snapshot the page (`WKWebView.takeSnapshot`) and slide the updated web view in over it; reverse on back. Close to a real `UINavigationController` feel with one web view. Polish with edge cases (rapid taps, slow loads); worth doing if B feels abrupt.

## Implementation (B)

- `shared/src/iosMain/.../web/SubstraitScreen.ios.kt` publishes the `SubstraitWebView` it creates through `web.bridge.SubstraitWebViewRegistry` so native SwiftUI code can observe and drive it.
- `apps/ios/Navigation/WebNavigation.swift` observes `canGoBack`, `title` and `url` via KVO and decides whether to show the back button.
- `apps/ios/Navigation/NavigationBar.swift` draws the bar (back button, title, AirPlay) over the full-screen web view. The bar is 44 pt and added to the page's safe area, so Substrait's fixed header sits below it while content scrolls underneath the bar's blurred background.

Verified in the simulator with XCUITest: on Explore (`/browse`) the bar shows no back button or title; opening a list shows the back chevron and the list title ("2026 — @ollie") with the cover image scrolling under the blurred bar; tapping back returns to Explore. The top-level paths in `WebNavigation.topLevelPaths` are partly guessed from Substrait's manifest shortcuts (`/browse`, `/feed/immersive`, `/you/lists`); the other bottom tabs haven't been checked yet.
