package com.flyr.android.features.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun HomeScreen(
    viewModel: HomeViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "FLYR",
            style = MaterialTheme.typography.headlineMedium,
        )
        if (uiState.isLoading) {
            CircularProgressIndicator()
        } else {
            Text(
                text = "Campaigns loaded: ${uiState.campaigns.size}",
                style = MaterialTheme.typography.titleMedium,
            )
            uiState.campaigns.forEach { campaign ->
                Text(
                    text = "${campaign.name} · ${campaign.territoryName ?: "No territory"}",
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        }
        Text(
            text = "Android shell for the campaign home flow. Port `HomeView` and campaign context here first.",
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

