package com.flyr.android.features.leads

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
fun LeadsScreen(
    viewModel: LeadsViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = "Leads",
            style = MaterialTheme.typography.headlineMedium,
        )
        Text(
            text = "Tracked leads: ${uiState.totalLeads}",
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            text = "Use this screen for the Android version of contacts, CRM sync, and lead workflows.",
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

