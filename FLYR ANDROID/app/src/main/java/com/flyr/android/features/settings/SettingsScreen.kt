package com.flyr.android.features.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.flyr.android.app.RootUiState
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun SettingsScreen(
    uiState: RootUiState,
    onSignOut: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Settings",
            style = MaterialTheme.typography.headlineMedium,
        )
        Text(
            text = uiState.workspaceName ?: "No workspace connected",
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            text = uiState.authState.email ?: "Signed out",
            style = MaterialTheme.typography.bodyLarge,
        )
        Text(
            text = if (uiState.authState.isDemoMode) {
                "Session source: demo"
            } else {
                "Session source: ${uiState.authState.authProvider ?: "supabase"}"
            },
            style = MaterialTheme.typography.bodyLarge,
        )
        uiState.authState.role?.let { role ->
            Text(
                text = "Workspace role: $role",
                style = MaterialTheme.typography.bodyLarge,
            )
        }
        uiState.authState.accessReason?.let { reason ->
            Text(
                text = "Access status: $reason",
                style = MaterialTheme.typography.bodyLarge,
            )
        }
        Text(
            text = "Port authentication settings, workspace preferences, integrations, and billing here.",
            style = MaterialTheme.typography.bodyLarge,
        )
        Button(onClick = onSignOut) {
            Text("Sign Out")
        }
    }
}
