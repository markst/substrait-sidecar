import Shared
import WebKit

/// Observes the Substrait web view's back/forward state and title for the native navigation bar.
/// Substrait is a single-page app; WebKit records its `history.pushState` navigations in the
/// back/forward list, so `canGoBack` and `url` update on every in-app screen change.
@MainActor
final class WebNavigation: ObservableObject {
    @Published private(set) var showsBack = false
    @Published private(set) var title = ""

    /// Substrait's top-level screens (bottom tabs and sign-in); like tab roots, they get no back button.
    private static let topLevelPaths: Set<String> = [
        "/", "/browse", "/feed", "/feed/immersive", "/search", "/you", "/you/lists", "/library",
        "/sign-in", "/sign-up", "/launch.html",
    ]
    private static let titleSuffixes = [" - Substrait", " | Substrait", " · Substrait", " — Substrait"]

    private weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []

    init() {
        SubstraitWebViewRegistry.shared.observe { [weak self] webView in
            MainActor.assumeIsolated { self?.attach(webView) }
        }
    }

    func goBack() {
        webView?.goBack()
    }

    private func attach(_ webView: WKWebView) {
        self.webView = webView
        let changed: (WKWebView) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }
        observations = [
            webView.observe(\.canGoBack) { view, _ in changed(view) },
            webView.observe(\.url) { view, _ in changed(view) },
            webView.observe(\.title) { view, _ in changed(view) },
        ]
        update()
    }

    private func update() {
        guard let webView else { return }
        let topLevel = Self.topLevelPaths.contains(Self.normalizedPath(webView.url))
        showsBack = webView.canGoBack && !topLevel
        title = topLevel ? "" : Self.displayTitle(webView.title)
    }

    private static func normalizedPath(_ url: URL?) -> String {
        guard let path = url?.path, !path.isEmpty else { return "/" }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func displayTitle(_ title: String?) -> String {
        guard var title = title?.trimmingCharacters(in: .whitespaces), title != "Substrait" else { return "" }
        for suffix in titleSuffixes where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
        }
        return title
    }
}
