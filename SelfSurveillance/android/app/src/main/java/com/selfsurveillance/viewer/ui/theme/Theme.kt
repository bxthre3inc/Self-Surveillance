package com.selfsurveillance.viewer.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColors = darkColorScheme(
    primary         = Color(0xFF64FFDA),
    onPrimary       = Color(0xFF00382D),
    primaryContainer = Color(0xFF005140),
    secondary       = Color(0xFF4FC3F7),
    background      = Color(0xFF0D1117),
    surface         = Color(0xFF161B22),
    surfaceVariant  = Color(0xFF1C2128),
    onBackground    = Color(0xFFE6EDF3),
    onSurface       = Color(0xFFE6EDF3),
    onSurfaceVariant = Color(0xFF8B949E),
    error           = Color(0xFFFF5370),
    outline         = Color(0xFF30363D)
)

@Composable
fun SSViewerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColors,
        content     = content
    )
}
