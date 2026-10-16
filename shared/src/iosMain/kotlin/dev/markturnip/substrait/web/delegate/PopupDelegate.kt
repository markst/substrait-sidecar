package dev.markturnip.substrait.web.delegate

import kotlinx.cinterop.ExperimentalForeignApi
import platform.UIKit.UIViewController
import platform.WebKit.WKNavigationAction
import platform.WebKit.WKUIDelegateProtocol
import platform.WebKit.WKWebView
import platform.WebKit.WKWebViewConfiguration
import platform.WebKit.WKWindowFeatures
import platform.darwin.NSObject

/** Presents `window.open` pop-ups (provider sign-in) modally and dismisses them on `window.close()`. */
internal class PopupDelegate : NSObject(), WKUIDelegateProtocol {
    @OptIn(ExperimentalForeignApi::class)
    override fun webView(
        webView: WKWebView,
        createWebViewWithConfiguration: WKWebViewConfiguration,
        forNavigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
    ): WKWebView? {
        val child = WKWebView(frame = webView.bounds, configuration = createWebViewWithConfiguration)
        child.UIDelegate = this
        val controller = UIViewController(nibName = null, bundle = null)
        controller.view = child
        var presenter = webView.window?.rootViewController ?: return null
        while (true) presenter = presenter.presentedViewController ?: break
        presenter.presentViewController(controller, animated = true, completion = null)
        return child
    }

    override fun webViewDidClose(webView: WKWebView) {
        var controller = webView.window?.rootViewController
        while (controller != null) {
            val presented = controller.presentedViewController
            if (presented?.view == webView) {
                controller.dismissViewControllerAnimated(true, completion = null)
                return
            }
            controller = presented
        }
    }
}
