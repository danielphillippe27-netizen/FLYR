package com.flyr.android.data.services

import com.flyr.android.app.AppRoute
import com.flyr.android.core.AppConfig
import com.flyr.android.data.storage.SessionStorage
import com.flyr.android.features.auth.AuthState
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

data class AccessResolution(
    val authState: AuthState,
    val route: AppRoute,
)

data class OnboardingRequest(
    val firstName: String,
    val lastName: String,
    val workspaceName: String,
    val industry: String,
    val useCase: String,
    val inviteEmails: List<String> = emptyList(),
)

private data class AccessStateResponse(
    val userId: String?,
    val role: String?,
    val workspaceName: String?,
    val workspaceId: String?,
    val hasAccess: Boolean,
    val reason: String?,
)

private data class AccessRedirectResponse(
    val redirect: String,
    val path: String,
)

interface AccessService {
    suspend fun resolve(authState: AuthState): AccessResolution
    suspend fun createCheckoutSession(
        plan: String,
        currency: String,
        priceId: String? = null,
    ): String
    suspend fun completeOnboarding(
        authState: AuthState,
        request: OnboardingRequest,
    ): AccessResolution
}

class DefaultAccessService(
    private val sessionStorage: SessionStorage,
    private val fallbackRouterService: AccessRouterService,
    private val supabaseClient: SupabaseClient? = null,
) : AccessService {
    override suspend fun resolve(authState: AuthState): AccessResolution {
        if (!authState.isSignedIn || authState.isDemoMode || supabaseClient == null) {
            return fallback(authState)
        }

        val accessState = runCatching { getState() }.getOrNull()
        val accessRedirect = runCatching { getRedirect() }.getOrNull()

        val mergedAuthState = authState.copy(
            workspaceId = accessState?.workspaceId?.takeUnless(String::isBlank) ?: authState.workspaceId,
            workspaceName = accessState?.workspaceName?.takeUnless(String::isBlank) ?: authState.workspaceName,
            role = accessState?.role?.takeUnless(String::isBlank) ?: authState.role,
            accessReason = accessState?.reason?.takeUnless(String::isBlank) ?: authState.accessReason,
            isDemoMode = false,
        )
        sessionStorage.saveAuthState(mergedAuthState)

        return AccessResolution(
            authState = mergedAuthState,
            route = resolveRoute(mergedAuthState, accessState, accessRedirect),
        )
    }

    override suspend fun completeOnboarding(
        authState: AuthState,
        request: OnboardingRequest,
    ): AccessResolution {
        if (!authState.isSignedIn || authState.isDemoMode || supabaseClient == null) {
            error("Real onboarding requires an authenticated Supabase session.")
        }

        authorizedPost(
            path = "/api/onboarding/complete",
            body = JSONObject().apply {
                put("firstName", request.firstName)
                put("lastName", request.lastName)
                put("workspaceName", request.workspaceName)
                put("industry", request.industry)
                put("useCase", request.useCase)
                put("inviteEmails", request.inviteEmails)
            },
        )

        val updatedAuthState = authState.copy(
            workspaceName = request.workspaceName,
            displayName = listOf(request.firstName, request.lastName)
                .joinToString(" ")
                .trim()
                .ifBlank { authState.displayName },
        )
        return resolve(updatedAuthState)
    }

    override suspend fun createCheckoutSession(
        plan: String,
        currency: String,
        priceId: String?,
    ): String {
        if (supabaseClient == null) {
            error("Real checkout requires a configured Supabase session.")
        }

        val payload = authorizedPost(
            path = "/api/billing/stripe/checkout",
            body = JSONObject().apply {
                put("plan", plan)
                put("currency", currency)
                if (!priceId.isNullOrBlank()) {
                    put("priceId", priceId)
                }
            },
        )

        return payload.stringOrNull("url")
            ?: error("Stripe checkout did not return a usable redirect URL.")
    }

    private suspend fun fallback(authState: AuthState): AccessResolution {
        sessionStorage.saveAuthState(authState)
        return AccessResolution(
            authState = authState,
            route = fallbackRouterService.resolveRoute(authState),
        )
    }

    private suspend fun resolveRoute(
        authState: AuthState,
        accessState: AccessStateResponse?,
        accessRedirect: AccessRedirectResponse?,
    ): AppRoute {
        val fallback = fallbackRoute(authState, accessState)
        val redirect = accessRedirect?.redirect?.trim()?.lowercase()
        val memberInactive = isMemberInactive(accessState, accessRedirect)

        return when (redirect) {
            null, "", "login" -> fallback
            "dashboard" -> {
                if (accessState?.hasAccess == false) {
                    AppRoute.Subscribe(memberInactive = memberInactive)
                } else {
                    AppRoute.Dashboard
                }
            }
            "subscribe", "contact-owner" -> AppRoute.Subscribe(memberInactive = memberInactive)
            "onboarding" -> recoverOnboardingRoute(authState, accessState)
            else -> fallback
        }
    }

    private suspend fun fallbackRoute(
        authState: AuthState,
        accessState: AccessStateResponse?,
    ): AppRoute {
        val workspaceId = accessState?.workspaceId?.takeUnless(String::isBlank) ?: authState.workspaceId
        return when {
            workspaceId.isNullOrBlank() -> AppRoute.Onboarding
            accessState?.hasAccess == false -> {
                AppRoute.Subscribe(memberInactive = isMemberInactive(accessState, null))
            }
            else -> AppRoute.Dashboard
        }
    }

    private fun recoverOnboardingRoute(
        authState: AuthState,
        accessState: AccessStateResponse?,
    ): AppRoute {
        val workspaceId = accessState?.workspaceId?.takeUnless(String::isBlank) ?: authState.workspaceId
        return when {
            workspaceId.isNullOrBlank() -> AppRoute.Onboarding
            accessState?.hasAccess == false -> {
                AppRoute.Subscribe(memberInactive = isMemberInactive(accessState, null))
            }
            else -> AppRoute.Dashboard
        }
    }

    private fun isMemberInactive(
        accessState: AccessStateResponse?,
        accessRedirect: AccessRedirectResponse?,
    ): Boolean {
        if (accessState?.reason.equals("member-inactive", ignoreCase = true)) {
            return true
        }

        val path = accessRedirect?.path.orEmpty()
        return path.contains("reason=member-inactive", ignoreCase = true)
    }

    private suspend fun getState(): AccessStateResponse {
        val payload = authorizedGet("/api/access/state")
        return AccessStateResponse(
            userId = payload.stringOrNull("user_id", "userId"),
            role = payload.stringOrNull("role"),
            workspaceName = payload.stringOrNull("name", "workspaceName"),
            workspaceId = payload.stringOrNull("workspace_id", "workspaceId"),
            hasAccess = payload.booleanOrDefault(true, "has_access", "hasAccess"),
            reason = payload.stringOrNull("reason"),
        )
    }

    private suspend fun getRedirect(): AccessRedirectResponse {
        val payload = authorizedGet("/api/access/redirect")
        return AccessRedirectResponse(
            redirect = payload.stringOrNull("redirect").orEmpty(),
            path = payload.stringOrNull("path").orEmpty(),
        )
    }

    private suspend fun authorizedGet(path: String): JSONObject {
        return authorizedRequest(
            path = path,
            method = "GET",
            body = null,
        )
    }

    private suspend fun authorizedPost(path: String, body: JSONObject): JSONObject {
        return authorizedRequest(
            path = path,
            method = "POST",
            body = body,
        )
    }

    private suspend fun authorizedRequest(
        path: String,
        method: String,
        body: JSONObject?,
    ): JSONObject {
        val session = supabaseClient?.auth?.currentSessionOrNull()
            ?: error("No active Supabase session is available for Android access routing.")
        val requestUrl = URL("${AppConfig.normalizedFlyrApiUrl}$path")
        val connection = (requestUrl.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 10_000
            readTimeout = 10_000
            setRequestProperty("Authorization", "Bearer ${session.accessToken}")
            setRequestProperty("Accept", "application/json")
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }

        return try {
            if (body != null) {
                connection.outputStream.bufferedWriter().use { writer ->
                    writer.write(body.toString())
                }
            }

            val statusCode = connection.responseCode
            val body = (if (statusCode in 200..299) connection.inputStream else connection.errorStream)
                ?.bufferedReader()
                ?.use { it.readText() }
                .orEmpty()

            if (statusCode !in 200..299) {
                val errorMessage = runCatching {
                    JSONObject(body).stringOrNull("error", "message")
                }.getOrNull()
                error(
                    errorMessage
                        ?: "FLYR access request failed with HTTP $statusCode for $path."
                )
            }

            JSONObject(body.ifBlank { "{}" })
        } finally {
            connection.disconnect()
        }
    }
}

private fun JSONObject.stringOrNull(vararg keys: String): String? {
    for (key in keys) {
        if (has(key) && !isNull(key)) {
            return optString(key).trim().takeUnless(String::isBlank)
        }
    }
    return null
}

private fun JSONObject.booleanOrDefault(defaultValue: Boolean, vararg keys: String): Boolean {
    for (key in keys) {
        if (has(key) && !isNull(key)) {
            return optBoolean(key, defaultValue)
        }
    }
    return defaultValue
}
