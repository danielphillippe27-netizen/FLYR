package com.flyr.android.core

data class AppUiState(
    val isAuthenticated: Boolean = false,
    val activeCampaignId: String? = null,
    val showBottomBar: Boolean = true,
)

