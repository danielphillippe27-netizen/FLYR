package com.flyr.android.designsystem.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = FlyrBlue,
    secondary = FlyrGreen,
    background = FlyrSurface,
    surface = FlyrWhite,
    onPrimary = FlyrWhite,
    onSecondary = FlyrBlack,
    onBackground = FlyrBlack,
    onSurface = FlyrBlack,
)

private val DarkColors = darkColorScheme(
    primary = FlyrBlue,
    secondary = FlyrGreen,
    background = FlyrBlack,
    surface = ColorTokens.DarkSurface,
    onPrimary = FlyrWhite,
    onSecondary = FlyrBlack,
    onBackground = FlyrWhite,
    onSurface = FlyrWhite,
)

@Composable
fun FlyrTheme(
    content: @Composable () -> Unit,
) {
    val colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors

    MaterialTheme(
        colorScheme = colorScheme,
        typography = FlyrTypography,
        content = content,
    )
}

private object ColorTokens {
    val DarkSurface = FlyrBlack.copy(alpha = 0.92f)
}
