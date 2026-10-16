package dev.markturnip.substrait.web

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.UIKitInteropInteractionMode
import androidx.compose.ui.viewinterop.UIKitInteropProperties
import androidx.compose.ui.viewinterop.UIKitView
import dev.markturnip.substrait.web.bridge.SubstraitWebViewRegistry
import dev.markturnip.substrait.web.view.SubstraitWebView

@Composable
actual fun SubstraitScreen(modifier: Modifier) {
    val webView = remember { SubstraitWebView.create().also(SubstraitWebViewRegistry::publish) }

    // The navigation bar (back, title, AirPlay) lives in SwiftUI (apps/ios), observing this web view
    // through SubstraitWebViewRegistry; AVRoutePickerView doesn't respond inside UIKitView.
    UIKitView(
        factory = { webView },
        modifier = modifier,
        properties = UIKitInteropProperties(
            interactionMode = UIKitInteropInteractionMode.NonCooperative,
            isNativeAccessibilityEnabled = true,
        ),
    )
}
