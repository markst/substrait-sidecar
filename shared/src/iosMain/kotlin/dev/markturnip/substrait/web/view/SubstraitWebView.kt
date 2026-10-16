package dev.markturnip.substrait.web.view

import dev.markturnip.substrait.web.SUBSTRAIT_START_URL
import dev.markturnip.substrait.web.delegate.NavigationDelegate
import dev.markturnip.substrait.web.delegate.PopupDelegate
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.readValue
import kotlinx.cinterop.useContents
import platform.CoreGraphics.CGRectZero
import platform.Foundation.NSSelectorFromString
import platform.Foundation.NSURL
import platform.Foundation.NSURLRequest
import platform.UIKit.UIEdgeInsetsMake
import platform.WebKit.WKAudiovisualMediaTypeNone
import platform.WebKit.WKWebView
import platform.WebKit.WKWebViewConfiguration

/** The Substrait `WKWebView`: media/AirPlay configuration, delegates and safe-area handling. */
@OptIn(ExperimentalForeignApi::class)
internal class SubstraitWebView private constructor(
    configuration: WKWebViewConfiguration,
) : WKWebView(frame = CGRectZero.readValue(), configuration = configuration) {
    // WebKit holds delegates weakly; the web view keeps them alive.
    private val navigationHandler = NavigationDelegate()
    private val popupHandler = PopupDelegate()

    init {
        allowsBackForwardNavigationGestures = true
        navigationDelegate = navigationHandler
        UIDelegate = popupHandler
    }

    /**
     * The web view fills the screen, and Substrait (viewport-fit=cover) only pads its fixed header for the
     * safe area, so its scrolling content would start under the notch. Reporting the top safe area (status
     * bar + iosApp's navigation bar) as obscured makes the content start below it yet still scroll beneath.
     */
    override fun safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        // obscuredContentInsets is iOS 26+.
        if (!respondsToSelector(NSSelectorFromString("setObscuredContentInsets:"))) return
        val top = safeAreaInsets.useContents { top }
        if (obscuredContentInsets.useContents { this.top } != top) {
            obscuredContentInsets = UIEdgeInsetsMake(top, 0.0, 0.0, 0.0)
        }
    }

    companion object {
        fun create(): SubstraitWebView {
            val configuration = WKWebViewConfiguration().apply {
                allowsInlineMediaPlayback = true
                mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone
                allowsAirPlayForMediaPlayback = true
                applicationNameForUserAgent = "Version/26.0 Mobile/15E148 Safari/604.1"
            }
            return SubstraitWebView(configuration).apply {
                loadRequest(NSURLRequest(NSURL(string = SUBSTRAIT_START_URL)))
            }
        }
    }
}
