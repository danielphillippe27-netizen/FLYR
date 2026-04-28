package com.flyr.android.app

import androidx.compose.runtime.Composable

@Composable
fun FlyrDashboard(
    uiState: RootUiState,
    onSignOut: () -> Unit,
) {
    FlyrAndroidApp(
        rootUiState = uiState,
        onSignOut = onSignOut,
    )
}
