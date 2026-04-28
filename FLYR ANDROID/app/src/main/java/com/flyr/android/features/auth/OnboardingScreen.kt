package com.flyr.android.features.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun OnboardingScreen(
    isSubmitting: Boolean,
    errorMessage: String?,
    onComplete: (String, String, String, String, String, String) -> Unit,
    onPreview: () -> Unit,
) {
    var firstName by rememberSaveable { mutableStateOf("") }
    var lastName by rememberSaveable { mutableStateOf("") }
    var workspaceName by rememberSaveable { mutableStateOf("") }
    var industry by rememberSaveable { mutableStateOf("Real Estate") }
    var useCase by rememberSaveable { mutableStateOf("solo") }
    var inviteEmails by rememberSaveable { mutableStateOf("") }

    val industries = listOf(
        "Real Estate",
        "Logistics",
        "Sales",
        "Pest Control",
        "HVAC",
        "Insurance",
        "Solar",
        "Other",
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = "Workspace Onboarding",
            style = MaterialTheme.typography.headlineMedium,
        )
        Text(
            text = "Finish the owner setup so Android follows the same access path as iOS and the web app.",
            style = MaterialTheme.typography.bodyLarge,
        )
        OutlinedTextField(
            value = firstName,
            onValueChange = { firstName = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("First Name") },
            enabled = !isSubmitting,
            singleLine = true,
        )
        OutlinedTextField(
            value = lastName,
            onValueChange = { lastName = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Last Name") },
            enabled = !isSubmitting,
            singleLine = true,
        )
        OutlinedTextField(
            value = workspaceName,
            onValueChange = { workspaceName = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Workspace Name") },
            enabled = !isSubmitting,
            singleLine = true,
        )
        Text(
            text = "Industry",
            style = MaterialTheme.typography.titleMedium,
        )
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            industries.chunked(2).forEach { row ->
                androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { option ->
                        OutlinedButton(
                            onClick = { industry = option },
                            enabled = !isSubmitting,
                        ) {
                            Text(if (industry == option) "$option*" else option)
                        }
                    }
                }
            }
        }
        Text(
            text = "Use Case",
            style = MaterialTheme.typography.titleMedium,
        )
        androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = { useCase = "solo" },
                enabled = !isSubmitting,
            ) {
                Text(if (useCase == "solo") "Solo*" else "Solo")
            }
            OutlinedButton(
                onClick = { useCase = "team" },
                enabled = !isSubmitting,
            ) {
                Text(if (useCase == "team") "Team*" else "Team")
            }
        }
        if (useCase == "team") {
            OutlinedTextField(
                value = inviteEmails,
                onValueChange = { inviteEmails = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Invite Emails") },
                placeholder = { Text("comma or newline separated") },
                enabled = !isSubmitting,
                minLines = 3,
            )
        }
        Button(
            onClick = {
                onComplete(
                    firstName,
                    lastName,
                    workspaceName,
                    industry,
                    useCase,
                    inviteEmails,
                )
            },
            enabled = !isSubmitting,
        ) {
            Text(if (isSubmitting) "Saving..." else "Complete Onboarding")
        }
        OutlinedButton(
            onClick = onPreview,
            enabled = !isSubmitting,
        ) {
            Text("Use Preview Workspace Instead")
        }
        if (!errorMessage.isNullOrBlank()) {
            Text(
                text = errorMessage,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}
