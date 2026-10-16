package dev.markturnip.substrait.web

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** Hosts the Substrait web player in the platform's native web view. */
@Composable
expect fun SubstraitScreen(modifier: Modifier)
