package com.flyr.android.app

import com.flyr.android.features.auth.AuthState

data class RootUiState(
    val route: AppRoute = AppRoute.Loading,
    val authState: AuthState = AuthState(),
    val workspaceName: String? = null,
    val isLoading: Boolean = true,
    val isSupabaseConfigured: Boolean = false,
    val isAuthSubmitting: Boolean = false,
    val authErrorMessage: String? = null,
    val externalUrlToOpen: String? = null,
)
