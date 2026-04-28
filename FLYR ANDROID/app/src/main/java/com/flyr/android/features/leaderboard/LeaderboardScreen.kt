package com.flyr.android.features.leaderboard

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
fun LeaderboardScreen(
    viewModel: LeaderboardViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Leaderboard",
            style = MaterialTheme.typography.headlineMedium,
        )
        uiState.entries.forEachIndexed { index, entry ->
            Text(
                text = "${index + 1}. ${entry.userName} - ${entry.score}",
                style = MaterialTheme.typography.bodyLarge,
            )
        }
        Text(
            text = "Android home for stats snapshots, rankings, and performance reporting.",
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

