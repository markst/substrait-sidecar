import AppKit
import WebKit

private let startURL = URL(string: "https://substra.it/browse")!
private let inAppSchemes: Set<String> = ["http", "https", "about", "blob", "data"]
private let messageHandlerName = "substraitAirPlay"

@MainActor
final class WebPlayer: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    @Published private(set) var airPlay = AirPlayState()

    /// PID of the WebKit GPU process that renders this web view's audio (WebKit SPI), or nil
    /// before any media has played or if the SPI is unavailable.
    var gpuProcessIdentifier: pid_t? {
        let selector = NSSelectorFromString("_gpuProcessIdentifier")
        guard webView.responds(to: selector),
              let pid = (webView.value(forKey: "_gpuProcessIdentifier") as? NSNumber)?.int32Value,
              pid > 0 else { return nil }
        return pid
    }

    private var activeFrame: WKFrameInfo?
    private var activeFrameId: String?
    private var popups: [WKWebView: NSWindow] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"

        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(
            source: Self.bundledScript("disable-mse"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        ))
        controller.addUserScript(WKUserScript(
            source: Self.bundledScript("airplay-bridge"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        ))

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        controller.add(WeakScriptMessageHandler(self), contentWorld: .page, name: messageHandlerName)
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: startURL))
    }

    private static func bundledScript(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("missing \(name).js")
        }
        return source
    }

    // MARK: AirPlay

    /// WebKit opens the AirPlay picker only from a trusted in-page gesture, so arm an invisible
    /// overlay in the active frame (see airplay-bridge.js) and click it with a real mouse event.
    /// WebKit anchors the picker at the click point, so for main-frame media the click is placed
    /// so the picker hangs from the top edge directly below the pointer (i.e. the toolbar button).
    func showAirPlayPicker() {
        guard let frame = activeFrame, let frameId = activeFrameId else { return }
        let toolbarAnchor = frame.isMainFrame ? viewportPointBelowPointer() : nil
        Task { @MainActor in
            do {
                let point: CGPoint
                if let toolbarAnchor {
                    point = toolbarAnchor
                } else {
                    let framePoint = try await webView.callAsyncJavaScript(
                        "return window.__substraitFramePoint ? window.__substraitFramePoint(id) : null",
                        arguments: ["id": frameId],
                        contentWorld: .page
                    ) as? [String: Any]
                    guard let x = (framePoint?["x"] as? NSNumber)?.doubleValue,
                          let y = (framePoint?["y"] as? NSNumber)?.doubleValue else { return }
                    point = CGPoint(x: x, y: y)
                }
                let armed = try await webView.callAsyncJavaScript(
                    "return window.__substraitArmAirPlayPicker ? window.__substraitArmAirPlayPicker() : false",
                    in: frame,
                    contentWorld: .page
                ) as? Bool
                guard armed == true else { return }
                clickWebView(atViewportPoint: point)
            } catch {
                resetAirPlay()
            }
        }
    }

    private var contentInsets: NSEdgeInsets {
        if #available(macOS 26.0, *) { return webView.obscuredContentInsets }
        return NSEdgeInsetsZero
    }

    /// CSS-pixel click point that makes the picker anchor at the top edge of the web view,
    /// horizontally under the mouse pointer. WebKit mirrors the click's y within the view when
    /// positioning the picker (observed on macOS 26.5), so the click goes near the bottom edge,
    /// but 40pt clear of the edges: a mouse-down in the window's resize margins/corner starts a
    /// live resize instead of reaching the page.
    private func viewportPointBelowPointer() -> CGPoint? {
        guard let window = webView.window else { return nil }
        let inset = contentInsets
        let scale = webView.pageZoom * webView.magnification
        let pointer = webView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let viewportWidth = (webView.bounds.width - inset.left - inset.right) / scale
        let viewportHeight = (webView.bounds.height - inset.top - inset.bottom) / scale
        let edgeMargin = 40 / scale
        let x = (pointer.x - inset.left) / scale
        return CGPoint(
            x: min(max(x, edgeMargin), viewportWidth - edgeMargin),
            y: max(viewportHeight - edgeMargin, 0)
        )
    }

    /// Sends a left click to the web view at a CSS-pixel point in the top-level viewport.
    private func clickWebView(atViewportPoint cssPoint: CGPoint) {
        guard let window = webView.window else { return }
        let inset = contentInsets
        let scale = webView.pageZoom * webView.magnification
        let x = inset.left + cssPoint.x * scale
        let yFromTop = inset.top + cssPoint.y * scale
        let viewPoint = NSPoint(x: x, y: webView.isFlipped ? yFromTop : webView.bounds.height - yFromTop)
        let location = webView.convert(viewPoint, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) else { return }
            window.sendEvent(event)
        }
    }

    private func resetAirPlay() {
        activeFrame = nil
        activeFrameId = nil
        airPlay = AirPlayState()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let frameId = body["frameId"] as? String else { return }
        let flag = { (key: String) in body[key] as? Bool ?? false }
        if flag("playing") {
            activeFrame = message.frameInfo
            activeFrameId = frameId
        }
        guard frameId == activeFrameId else { return }
        airPlay = AirPlayState(
            hasMedia: true,
            available: flag("available"),
            wireless: flag("wireless"),
            remoteDisabled: flag("remoteDisabled"),
            mse: flag("mse")
        )
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        resetAirPlay()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView { resetAirPlay() }
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(),
              !inAppSchemes.contains(scheme) else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    // MARK: Pop-up windows (provider sign-in)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.uiDelegate = self
        child.navigationDelegate = self
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = child
        window.center()
        window.makeKeyAndOrderFront(nil)
        popups[child] = window
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.removeValue(forKey: webView)?.close()
    }
}

/// Forwards script messages without retaining the target, so closing the window frees the player.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
