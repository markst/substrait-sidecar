package dev.markturnip.substrait.web

const val SUBSTRAIT_START_URL = "https://substra.it/browse"

/** URL schemes that stay inside the web view; anything else is handed to the OS. */
val EXTERNAL_SAFE_SCHEMES = setOf("http", "https", "about", "blob", "data")
