package com.flyr.android.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flyr.android.core.AppConfig
import com.flyr.android.features.auth.AuthState
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class FlyrAppViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(RootUiState())
    val uiState: StateFlow<RootUiState> = _uiState.asStateFlow()

    init {
        bootstrap()
    }

    fun bootstrap() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    route = AppRoute.Loading,
                    isSupabaseConfigured = AppConfig.isSupabaseConfigured,
                    authErrorMessage = null,
                    externalUrlToOpen = null,
                )
            }
            runCatching { AppServices.authService.restoreSession() }
                .onSuccess { authState ->
                    updateFromAuth(authState)
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            route = AppRoute.Login,
                            authState = AuthState(),
                            workspaceName = null,
                            isLoading = false,
                            authErrorMessage = error.message ?: "We couldn't restore the previous Android session.",
                            externalUrlToOpen = null,
                        )
                    }
                }
        }
    }

    fun signInWithEmail(email: String, password: String) {
        viewModelScope.launch {
            val trimmedEmail = email.trim()
            if (trimmedEmail.isEmpty() || password.isBlank()) {
                _uiState.update {
                    it.copy(authErrorMessage = "Enter both email and password to sign in.")
                }
                return@launch
            }

            _uiState.update {
                it.copy(
                    isAuthSubmitting = true,
                    authErrorMessage = null,
                )
            }

            runCatching { AppServices.authService.signInWithEmail(trimmedEmail, password) }
                .onSuccess { authState ->
                    updateFromAuth(authState)
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isAuthSubmitting = false,
                            authErrorMessage = error.message ?: "Sign-in failed. Double-check your credentials and try again.",
                        )
                    }
                }
        }
    }

    fun enterDemoMode() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isAuthSubmitting = true,
                    authErrorMessage = null,
                )
            }
            runCatching { AppServices.authService.signInDemo() }
                .onSuccess { authState ->
                    updateFromAuth(authState)
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isAuthSubmitting = false,
                            authErrorMessage = error.message ?: "The Android demo session could not be started.",
                        )
                    }
                }
        }
    }

    fun activatePreviewWorkspace() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isAuthSubmitting = true,
                    authErrorMessage = null,
                )
            }
            runCatching { AppServices.authService.activatePreviewWorkspace() }
                .onSuccess { authState ->
                    updateFromAuth(authState)
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isAuthSubmitting = false,
                            authErrorMessage = error.message
                                ?: "We couldn't enter the preview workspace yet.",
                        )
                    }
                }
        }
    }

    fun completeOnboarding(
        firstName: String,
        lastName: String,
        workspaceName: String,
        industry: String,
        useCase: String,
        inviteEmails: String,
    ) {
        viewModelScope.launch {
            val trimmedFirstName = firstName.trim()
            val trimmedLastName = lastName.trim()
            val trimmedWorkspaceName = workspaceName.trim()
            val trimmedIndustry = industry.trim()
            val normalizedUseCase = useCase.trim().lowercase()
            val parsedInviteEmails = inviteEmails
                .split(",", "\n")
                .map(String::trim)
                .filter(String::isNotBlank)

            if (trimmedFirstName.isEmpty() ||
                trimmedLastName.isEmpty() ||
                trimmedWorkspaceName.isEmpty() ||
                trimmedIndustry.isEmpty()
            ) {
                _uiState.update {
                    it.copy(authErrorMessage = "Add your name, workspace name, and industry to finish onboarding.")
                }
                return@launch
            }

            _uiState.update {
                it.copy(
                    isAuthSubmitting = true,
                    authErrorMessage = null,
                )
            }

            runCatching {
                AppServices.accessService.completeOnboarding(
                    authState = uiState.value.authState,
                    request = com.flyr.android.data.services.OnboardingRequest(
                        firstName = trimmedFirstName,
                        lastName = trimmedLastName,
                        workspaceName = trimmedWorkspaceName,
                        industry = trimmedIndustry,
                        useCase = if (normalizedUseCase == "team") "team" else "solo",
                        inviteEmails = parsedInviteEmails,
                    ),
                )
            }.onSuccess { accessResolution ->
                _uiState.update {
                    it.copy(
                        route = accessResolution.route,
                        authState = accessResolution.authState,
                        workspaceName = accessResolution.authState.workspaceName,
                        isLoading = false,
                        isSupabaseConfigured = AppConfig.isSupabaseConfigured,
                        isAuthSubmitting = false,
                        authErrorMessage = null,
                        externalUrlToOpen = null,
                    )
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(
                        isAuthSubmitting = false,
                        authErrorMessage = error.message ?: "Android onboarding could not be completed just yet.",
                    )
                }
            }
        }
    }

    fun startCheckout(plan: String) {
        viewModelScope.launch {
            val normalizedPlan = plan.trim().lowercase()
            if (normalizedPlan !in setOf("monthly", "annual")) {
                _uiState.update {
                    it.copy(authErrorMessage = "Choose a valid plan before continuing to checkout.")
                }
                return@launch
            }

            _uiState.update {
                it.copy(
                    isAuthSubmitting = true,
                    authErrorMessage = null,
                )
            }

            runCatching {
                AppServices.accessService.createCheckoutSession(
                    plan = normalizedPlan,
                    currency = defaultCurrencyCode(),
                )
            }.onSuccess { checkoutUrl ->
                _uiState.update {
                    it.copy(
                        isAuthSubmitting = false,
                        authErrorMessage = null,
                        externalUrlToOpen = checkoutUrl,
                    )
                }
            }.onFailure { error ->
                _uiState.update {
                    it.copy(
                        isAuthSubmitting = false,
                        authErrorMessage = error.message
                            ?: "We couldn't start Stripe checkout just yet.",
                    )
                }
            }
        }
    }

    fun refreshAccess() {
        viewModelScope.launch {
            val authState = uiState.value.authState
            if (!authState.isSignedIn) return@launch
            updateFromAuth(authState)
        }
    }

    fun consumeExternalUrl(errorMessage: String? = null) {
        _uiState.update {
            it.copy(
                externalUrlToOpen = null,
                authErrorMessage = errorMessage ?: it.authErrorMessage,
                isAuthSubmitting = false,
            )
        }
    }

    fun signOut() {
        viewModelScope.launch {
            AppServices.authService.signOut()
            updateFromAuth(AuthState())
        }
    }

    private suspend fun updateFromAuth(authState: AuthState) {
        val accessResolution = AppServices.accessService.resolve(authState)
        _uiState.update {
            it.copy(
                route = accessResolution.route,
                authState = accessResolution.authState,
                workspaceName = accessResolution.authState.workspaceName,
                isLoading = false,
                isSupabaseConfigured = AppConfig.isSupabaseConfigured,
                isAuthSubmitting = false,
                authErrorMessage = null,
                externalUrlToOpen = null,
            )
        }
    }

    private fun defaultCurrencyCode(): String {
        val locale = Locale.getDefault()
        return if (locale.country.equals("CA", ignoreCase = true)) {
            "CAD"
        } else {
            "USD"
        }
    }
}
