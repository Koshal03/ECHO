package com.koshal.echotalk.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = PrimaryPurple,
    secondary = AccentCyan,
    background = BgDark,
    surface = SurfaceDark,
    onPrimary = TextPrimary,
    onSecondary = BgDark,
    onBackground = TextPrimary,
    onSurface = TextPrimary
)

@Composable
fun EchoTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
