package dev.markturnip.substrait.web

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Message
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

@Composable
actual fun SubstraitScreen(modifier: Modifier) {
    val context = LocalContext.current
    var popup by remember { mutableStateOf<WebView?>(null) }

    val webView = remember {
        lateinit var chromeClient: WebChromeClient
        val viewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (request.url.scheme?.lowercase() in EXTERNAL_SAFE_SCHEMES) return false
                try {
                    view.context.startActivity(Intent(Intent.ACTION_VIEW, request.url))
                } catch (_: ActivityNotFoundException) {
                }
                return true
            }
        }
        chromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                if (PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID in request.resources) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID))
                } else {
                    request.deny()
                }
            }

            override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
                val child = configuredWebView(view.context, viewClient, this)
                (resultMsg.obj as WebView.WebViewTransport).webView = child
                resultMsg.sendToTarget()
                popup = child
                return true
            }

            override fun onCloseWindow(window: WebView) {
                if (window === popup) {
                    window.destroy()
                    popup = null
                }
            }
        }
        configuredWebView(context, viewClient, chromeClient)
    }

    AndroidView(factory = { webView }, modifier = modifier.safeDrawingPadding())

    popup?.let { child ->
        Dialog(
            onDismissRequest = {
                child.destroy()
                popup = null
            },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            AndroidView(factory = { child }, modifier = Modifier.fillMaxSize())
        }
    }

    BackHandler(enabled = true) {
        if (webView.canGoBack()) webView.goBack() else (context as? Activity)?.moveTaskToBack(true)
    }

    DisposableEffect(Unit) {
        if (webView.url == null) webView.loadUrl(SUBSTRAIT_START_URL)
        onDispose {
            CookieManager.getInstance().flush()
            webView.destroy()
        }
    }
}

@SuppressLint("SetJavaScriptEnabled")
private fun configuredWebView(context: Context, viewClient: WebViewClient, chromeClient: WebChromeClient): WebView =
    WebView(context).apply {
        // AndroidView defaults to WRAP_CONTENT, which makes Chromium resolve vh/svh/dvh to 0 and collapses the page.
        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.mediaPlaybackRequiresUserGesture = false
        settings.setSupportMultipleWindows(true)
        settings.javaScriptCanOpenWindowsAutomatically = true
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
        webViewClient = viewClient
        webChromeClient = chromeClient
    }
