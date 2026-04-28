package com.flyr.android.core

data class SessionState(
    val isActive: Boolean = false,
    val sessionId: String? = null,
    val selectedCampaignName: String? = null,
)

