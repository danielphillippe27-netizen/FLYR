package com.flyr.android.features.auth

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun SubscribeScreen(
    memberInactive: Boolean,
    isSubmitting: Boolean,
    isOwner: Boolean,
    errorMessage: String?,
    onStartMonthlyCheckout: () -> Unit,
    onStartAnnualCheckout: () -> Unit,
    onContinue: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (memberInactive) {
            Surface(
                color = Color(0xFFFFF1E8),
                shape = RoundedCornerShape(8.dp),
            ) {
                Text(
                    text = if (isOwner) {
                        "Your workspace is inactive. Start a trial or choose a plan to restore access."
                    } else {
                        "Your workspace subscription is inactive. Please contact the workspace owner to reactivate access."
                    },
                    modifier = Modifier.padding(16.dp),
                    color = Color(0xFF8A3B12),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }

        Text(
            text = if (isOwner) "Unlock FLYR Pro" else "Workspace Access Needed",
            style = MaterialTheme.typography.headlineMedium,
        )
        Text(
            text = if (isOwner) {
                "Choose a plan to continue to Stripe checkout from Android. Access opens as soon as the workspace subscription is active."
            } else {
                "This workspace is billed through the owner account, so members cannot start checkout here. Once the owner reactivates billing, access will return automatically."
            },
            style = MaterialTheme.typography.bodyLarge,
        )

        if (isOwner) {
            PlanCard(
                title = "Annual",
                priceLine = "CA$419.99/year or $299.99/year",
                detailLine = "Best value for year-round outreach.",
                buttonLabel = "Start Annual Checkout",
                isSubmitting = isSubmitting,
                onStartCheckout = onStartAnnualCheckout,
            )
            PlanCard(
                title = "Monthly",
                priceLine = "CA$39.99/month or $29.99/month",
                detailLine = "Flexible billing for active teams.",
                buttonLabel = "Start Monthly Checkout",
                isSubmitting = isSubmitting,
                onStartCheckout = onStartMonthlyCheckout,
            )
        }

        if (!errorMessage.isNullOrBlank()) {
            Text(
                text = errorMessage,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium,
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        OutlinedButton(
            onClick = onContinue,
            enabled = !isSubmitting,
        ) {
            Text("Use Preview Workspace")
        }
    }
}

@Composable
private fun PlanCard(
    title: String,
    priceLine: String,
    detailLine: String,
    buttonLabel: String,
    isSubmitting: Boolean,
    onStartCheckout: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        shape = RoundedCornerShape(8.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                text = priceLine,
                style = MaterialTheme.typography.bodyLarge,
            )
            Text(
                text = detailLine,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(
                onClick = onStartCheckout,
                enabled = !isSubmitting,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (isSubmitting) "Redirecting..." else buttonLabel)
            }
        }
    }
}
