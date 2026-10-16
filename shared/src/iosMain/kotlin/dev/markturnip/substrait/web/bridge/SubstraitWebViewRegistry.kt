package dev.markturnip.substrait.web.bridge

import platform.WebKit.WKWebView

/**
 * Hands the Substrait web view created in Compose to native SwiftUI code (iosApp's navigation bar),
 * which observes its back/forward state and title.
 */
object SubstraitWebViewRegistry {
    private var webView: WKWebView? = null
    private val pending = mutableListOf<(WKWebView) -> Unit>()

    /** Calls [onAvailable] with the web view now if it exists, otherwise once it's created. */
    fun observe(onAvailable: (WKWebView) -> Unit) {
        val current = webView
        if (current != null) onAvailable(current) else pending += onAvailable
    }

    internal fun publish(webView: WKWebView) {
        this.webView = webView
        pending.forEach { it(webView) }
        pending.clear()
    }
}
