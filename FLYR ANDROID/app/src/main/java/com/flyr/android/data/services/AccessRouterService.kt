package com.flyr.android.data.services

import com.flyr.android.app.AppRoute
import com.flyr.android.features.auth.AuthState

interface AccessRouterService {
    suspend fun resolveRoute(authState: AuthState): AppRoute
}

class DefaultAccessRouterService : AccessRouterService {
    override suspend fun resolveRoute(authState: AuthState): AppRoute {
        return when {
            !authState.isSignedIn -> AppRoute.Login
            authState.workspaceName.isNullOrBlank() -> AppRoute.Onboarding
            authState.accessReason.equals("member-inactive", ignoreCase = true) -> {
                AppRoute.Subscribe(memberInactive = true)
            }
            else -> AppRoute.Dashboard
        }
    }
}
