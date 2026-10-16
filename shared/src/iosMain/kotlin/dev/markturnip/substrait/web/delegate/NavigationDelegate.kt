package dev.markturnip.substrait.web.delegate

import dev.markturnip.substrait.web.EXTERNAL_SAFE_SCHEMES
import kotlinx.cinterop.ObjCSignatureOverride
import platform.UIKit.UIApplication
import platform.WebKit.WKNavigationAction
import platform.WebKit.WKNavigationActionPolicy
import platform.WebKit.WKNavigationDelegateProtocol
import platform.WebKit.WKWebView
import platform.darwin.NSObject

/** Keeps web links in the web view, hands other schemes to the system, and reloads after a crash. */
internal class NavigationDelegate : NSObject(), WKNavigationDelegateProtocol {
    @ObjCSignatureOverride
    override fun webView(
        webView: WKWebView,
        decidePolicyForNavigationAction: WKNavigationAction,
        decisionHandler: (WKNavigationActionPolicy) -> Unit,
    ) {
        val url = decidePolicyForNavigationAction.request.URL
        val scheme = url?.scheme?.lowercase()
        if (url == null || scheme == null || scheme in EXTERNAL_SAFE_SCHEMES) {
            decisionHandler(WKNavigationActionPolicy.WKNavigationActionPolicyAllow)
            return
        }
        UIApplication.sharedApplication.openURL(url, options = emptyMap<Any?, Any>(), completionHandler = null)
        decisionHandler(WKNavigationActionPolicy.WKNavigationActionPolicyCancel)
    }

    override fun webViewWebContentProcessDidTerminate(webView: WKWebView) {
        webView.reload()
    }
}
