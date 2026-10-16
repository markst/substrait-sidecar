# iOS and Android apps

Both share a Kotlin Multiplatform / Compose Multiplatform UI in `shared/` that hosts the platform web view (`SubstraitScreen` with `expect`/`actual` per platform). `apps/android/` (Gradle module `:androidApp`) and `apps/ios/` are thin entry points (AGP 9 layout).

## Layout

`shared/src/<sourceSet>/kotlin/dev/markturnip/substrait/`:

| Package | Source sets | Contents |
|---|---|---|
| `app` | common, ios | `App` (root composable); iOS `MainViewController` entry point for Swift |
| `web` | common, android, ios | `SubstraitScreen` (`expect`/`actual` Compose host), `SubstraitConfig` |
| `web.view` | ios | `SubstraitWebView`: the `WKWebView` subclass (media/AirPlay config, owns its delegates, safe-area insets) |
| `web.delegate` | ios | `NavigationDelegate` (external links, crash reload), `PopupDelegate` (`window.open` sheets) |
| `web.bridge` | ios | `SubstraitWebViewRegistry`: hands the web view to Swift |

Under `apps/ios/`, each top-level folder is an Xcode 16 synchronized folder in `iosApp.xcodeproj` (new files are built automatically; a new top-level folder must be added to the project once):

| Folder | Contents |
|---|---|
| `App/` | `iOSApp` entry point, `ContentView` (web view + bar) |
| `Compose/` | `ComposeView`: hosts the shared Compose UI |
| `Navigation/` | `NavigationBar` and `WebNavigation` (back/title state) |
| `AirPlay/` | `AirPlayButton` (`AVRoutePickerView`) |
| `Resources/` | `Assets.xcassets`, `Info.plist` (excluded from membership, used via `INFOPLIST_FILE`), `Preview Content` |

## iOS

- `WKWebView` inside Compose (`UIKitView`), full-screen; Substrait uses `viewport-fit=cover` and pads its fixed header for the safe area.
- **Navigation bar:** a native SwiftUI bar (`apps/ios/Navigation/`) with a back button, the page title and the AirPlay button, over the full-screen web view. See [ios-navigation.md](ios-navigation.md) for the problem and the approaches considered.
- **AirPlay:** iOS routes audio per app, so a plain `AVRoutePickerView` is enough and other apps aren't affected. It lives in SwiftUI, not inside Compose's `UIKitView`, where taps didn't reach it. A zero-frame `AVRoutePickerView` ignores taps, so it's created at 44×44.
- **Safe areas:** the 44 pt bar is added to the page's safe area via `additionalSafeAreaInsets`, so Substrait's fixed header sits below it. A `WKWebView` subclass keeps `obscuredContentInsets.top` equal to the top safe area (iOS 26+), so scrolling content starts below the notch and the bar but still scrolls underneath.
- `AVAudioSession` category `.playback` with `.longFormAudio` policy, and `UIBackgroundModes: audio`. WebKit still pauses *video* (e.g. YouTube) when the app is backgrounded.

## Android

- `WebView` inside Compose (`AndroidView`).
- `AndroidView` gives the `WebView` `WRAP_CONTENT` layout params by default, which makes Chromium resolve `vh`/`svh`/`dvh` to 0 and collapses the page; explicit `MATCH_PARENT` fixes it.
- `RESOURCE_PROTECTED_MEDIA_ID` is granted for Widevine (Apple Music, TIDAL); other permission requests are denied.
- `window.open` pop-ups open in a full-screen dialog `WebView`; non-http(s) links go to the system.
- `configChanges` keeps the activity (and audio) alive across rotation.
- No casting. Streaming to a network speaker would need Android 10+ `AudioPlaybackCapture` (MediaProjection consent) feeding the same WAV-over-HTTP + DLNA approach as the Mac; untested whether Chromium's WebView audio is capturable.
