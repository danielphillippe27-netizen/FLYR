package com.flyr.android.features.auth

data class AuthState(
    val isSignedIn: Boolean = false,
    val userId: String? = null,
    val email: String? = null,
    val displayName: String? = null,
    val workspaceId: String? = null,
    val workspaceName: String? = null,
    val role: String? = null,
    val accessReason: String? = null,
    val authProvider: String? = null,
    val isDemoMode: Boolean = false,
)
