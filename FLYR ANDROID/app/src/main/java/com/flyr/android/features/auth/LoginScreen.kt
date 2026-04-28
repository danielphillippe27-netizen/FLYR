package com.flyr.android.features.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

@Composable
fun LoginScreen(
    isSupabaseConfigured: Boolean,
    isSubmitting: Boolean,
    errorMessage: String?,
    onEmailSignIn: (String, String) -> Unit,
    onContinue: () -> Unit,
) {
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = "Welcome to FLYR",
            style = MaterialTheme.typography.headlineMedium,
        )
        Text(
            text = if (isSupabaseConfigured) {
                "Sign in with the same Supabase project the iOS app already uses. Demo mode is still here as a fallback while we port the rest of the flows."
            } else {
                "Supabase config is still empty, so the Android app is using a persisted demo bootstrap for now."
            },
            style = MaterialTheme.typography.bodyLarge,
        )
        if (isSupabaseConfigured) {
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Email") },
                singleLine = true,
                enabled = !isSubmitting,
            )
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Password") },
                singleLine = true,
                enabled = !isSubmitting,
                visualTransformation = PasswordVisualTransformation(),
            )
            Button(
                onClick = { onEmailSignIn(email, password) },
                enabled = !isSubmitting,
            ) {
                Text(if (isSubmitting) "Signing In..." else "Sign In")
            }
            TextButton(
                onClick = onContinue,
                enabled = !isSubmitting,
            ) {
                Text("Use Demo Mode")
            }
        } else {
            Button(
                onClick = onContinue,
                enabled = !isSubmitting,
            ) {
                Text(if (isSubmitting) "Starting..." else "Continue")
            }
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
