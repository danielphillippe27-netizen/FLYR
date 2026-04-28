package com.flyr.android.features.record

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
fun RecordScreen(
    viewModel: RecordViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Record",
            style = MaterialTheme.typography.headlineMedium,
        )
        Text(
            text = if (uiState.isSessionActive) {
                "Session active"
            } else {
                "No active session"
            },
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            text = "This is the Android landing point for the session recorder, live map, and walk flow.",
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

