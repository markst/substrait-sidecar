package dev.markturnip.substrait.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import dev.markturnip.substrait.web.SubstraitScreen

/** Safe areas are handled per platform: Android pads in SubstraitScreen, iOS in SwiftUI (ContentView). */
@Composable
fun App() {
    MaterialTheme(colorScheme = darkColorScheme()) {
        Box(Modifier.fillMaxSize().background(Color(0xFF0A0A0A))) {
            SubstraitScreen(Modifier.fillMaxSize())
        }
    }
}
