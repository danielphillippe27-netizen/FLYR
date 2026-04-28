package com.flyr.android.data.storage

import android.content.Context
import android.content.SharedPreferences
import com.flyr.android.features.auth.AuthState

class SessionStorage(context: Context) {
    private val preferences: SharedPreferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun loadAuthState(): AuthState? {
        if (!preferences.getBoolean(KEY_IS_SIGNED_IN, false)) {
            return null
        }

        return AuthState(
            isSignedIn = true,
            userId = preferences.getString(KEY_USER_ID, null),
            email = preferences.getString(KEY_EMAIL, null),
            displayName = preferences.getString(KEY_DISPLAY_NAME, null),
            workspaceId = preferences.getString(KEY_WORKSPACE_ID, null),
            workspaceName = preferences.getString(KEY_WORKSPACE_NAME, null),
            role = preferences.getString(KEY_ROLE, null),
            accessReason = preferences.getString(KEY_ACCESS_REASON, null),
            authProvider = preferences.getString(KEY_AUTH_PROVIDER, null),
            isDemoMode = preferences.getBoolean(KEY_IS_DEMO_MODE, false),
        )
    }

    fun saveAuthState(authState: AuthState) {
        preferences.edit()
            .putBoolean(KEY_IS_SIGNED_IN, authState.isSignedIn)
            .putString(KEY_USER_ID, authState.userId)
            .putString(KEY_EMAIL, authState.email)
            .putString(KEY_DISPLAY_NAME, authState.displayName)
            .putString(KEY_WORKSPACE_ID, authState.workspaceId)
            .putString(KEY_WORKSPACE_NAME, authState.workspaceName)
            .putString(KEY_ROLE, authState.role)
            .putString(KEY_ACCESS_REASON, authState.accessReason)
            .putString(KEY_AUTH_PROVIDER, authState.authProvider)
            .putBoolean(KEY_IS_DEMO_MODE, authState.isDemoMode)
            .apply()
    }

    fun clear() {
        preferences.edit().clear().apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "flyr_session"
        const val KEY_IS_SIGNED_IN = "is_signed_in"
        const val KEY_USER_ID = "user_id"
        const val KEY_EMAIL = "email"
        const val KEY_DISPLAY_NAME = "display_name"
        const val KEY_WORKSPACE_ID = "workspace_id"
        const val KEY_WORKSPACE_NAME = "workspace_name"
        const val KEY_ROLE = "role"
        const val KEY_ACCESS_REASON = "access_reason"
        const val KEY_AUTH_PROVIDER = "auth_provider"
        const val KEY_IS_DEMO_MODE = "is_demo_mode"
    }
}
