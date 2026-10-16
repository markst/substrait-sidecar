import SwiftUI
import WebKit

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    /// Height of the window toolbar the web view extends under; the page lays out below it
    /// and scrolls underneath it.
    let topInset: CGFloat

    func makeNSView(context: Context) -> WKWebView { webView }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if #available(macOS 26.0, *), nsView.obscuredContentInsets.top != topInset {
            nsView.obscuredContentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        }
    }
}
