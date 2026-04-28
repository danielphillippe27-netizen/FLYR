package com.flyr.android.data.services

import com.flyr.android.core.AppConfig
import com.flyr.android.data.storage.SessionStorage
import com.flyr.android.features.auth.AuthState
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.createSupabaseClient

interface AuthService {
    suspend fun restoreSession(): AuthState
    suspend fun signInWithEmail(email: String, password: String): AuthState
    suspend fun signInDemo(): AuthState
    suspend fun activatePreviewWorkspace(): AuthState
    suspend fun signOut()
}

class SharedPrefsAuthService(
    private val sessionStorage: SessionStorage,
) : AuthService {
    override suspend fun restoreSession(): AuthState {
        return sessionStorage.loadAuthState() ?: AuthState()
    }

    override suspend fun signInWithEmail(email: String, password: String): AuthState {
        error("Supabase is not configured for this Android build.")
    }

    override suspend fun signInDemo(): AuthState {
        val authState = AuthState(
            isSignedIn = true,
            userId = "demo-user",
            email = "android@flyr.app",
            displayName = "Android Demo User",
            workspaceId = "demo-workspace",
            workspaceName = "Demo Workspace",
            role = "owner",
            authProvider = "demo",
            isDemoMode = true,
        )
        sessionStorage.saveAuthState(authState)
        return authState
    }

    override suspend fun activatePreviewWorkspace(): AuthState {
        val authState = (sessionStorage.loadAuthState() ?: AuthState()).copy(
            isSignedIn = true,
            workspaceId = "android-preview-workspace",
            workspaceName = "FLYR Android Preview",
            role = "owner",
        )
        sessionStorage.saveAuthState(authState)
        return authState
    }

    override suspend fun signOut() {
        sessionStorage.clear()
    }
}

class SupabaseAuthService(
    private val sessionStorage: SessionStorage,
    private val client: SupabaseClient,
) : AuthService {
    override suspend fun restoreSession(): AuthState {
        val session = client.auth.currentSessionOrNull()
            ?: return sessionStorage.loadAuthState()?.takeIf { it.isDemoMode } ?: AuthState()
        val user = session.user ?: error("Supabase restored a session without user details.")

        return buildAuthState(user.id, user.email, "supabase-email")
    }

    override suspend fun signInWithEmail(email: String, password: String): AuthState {
        client.auth.signInWith(Email) {
            this.email = email.trim()
            this.password = password
        }

        val session = client.auth.currentSessionOrNull()
            ?: error("Supabase sign-in completed without a local session.")
        val user = session.user ?: error("Supabase sign-in completed without user details.")

        return buildAuthState(user.id, user.email, "supabase-email")
    }

    override suspend fun signInDemo(): AuthState {
        val authState = AuthState(
            isSignedIn = true,
            userId = "demo-user",
            email = "android@flyr.app",
            displayName = "Android Demo User",
            workspaceId = "demo-workspace",
            workspaceName = "Demo Workspace",
            role = "owner",
            authProvider = "demo",
            isDemoMode = true,
        )
        sessionStorage.saveAuthState(authState)
        return authState
    }

    override suspend fun activatePreviewWorkspace(): AuthState {
        val currentState = restoreSession()
        check(currentState.isSignedIn) { "A signed-in user is required before entering the Android preview workspace." }

        val authState = currentState.copy(
            workspaceId = currentState.workspaceId ?: "android-preview-workspace",
            workspaceName = currentState.workspaceName ?: "FLYR Android Preview",
            role = currentState.role ?: "owner",
        )
        sessionStorage.saveAuthState(authState)
        return authState
    }

    override suspend fun signOut() {
        runCatching { client.auth.signOut() }
        sessionStorage.clear()
    }

    private fun buildAuthState(
        userId: String,
        email: String?,
        authProvider: String,
    ): AuthState {
        val persisted = sessionStorage.loadAuthState()
        val displayName = persisted?.displayName
            ?.takeUnless { it.isBlank() }
            ?: email
                ?.substringBefore("@")
                ?.replaceFirstChar { char ->
                    if (char.isLowerCase()) char.titlecase() else char.toString()
                }

        val authState = AuthState(
            isSignedIn = true,
            userId = userId,
            email = email,
            displayName = displayName,
            workspaceId = persisted?.workspaceId,
            workspaceName = persisted?.workspaceName,
            role = persisted?.role,
            accessReason = persisted?.accessReason,
            authProvider = authProvider,
            isDemoMode = false,
        )
        sessionStorage.saveAuthState(authState)
        return authState
    }
}

fun createFlyrSupabaseClient(): SupabaseClient {
    return createSupabaseClient(
        supabaseUrl = AppConfig.supabaseUrl,
        supabaseKey = AppConfig.supabaseAnonKey,
    ) {
        install(Auth)
    }
}
