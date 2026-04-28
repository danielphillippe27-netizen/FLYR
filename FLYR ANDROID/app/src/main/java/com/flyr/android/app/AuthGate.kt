package com.flyr.android.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalUriHandler
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.flyr.android.features.auth.LoginScreen
import com.flyr.android.features.auth.OnboardingScreen
import com.flyr.android.features.auth.SubscribeScreen

@Composable
fun AuthGate(
    viewModel: FlyrAppViewModel,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val uriHandler = LocalUriHandler.current
    val lifecycleOwner = LocalLifecycleOwner.current

    LaunchedEffect(uiState.externalUrlToOpen) {
        val url = uiState.externalUrlToOpen ?: return@LaunchedEffect
        val openError = runCatching {
            uriHandler.openUri(url)
        }.exceptionOrNull()

        viewModel.consumeExternalUrl(
            errorMessage = openError?.message
                ?: if (openError != null) "We couldn't open the checkout link on Android." else null,
        )
    }

    DisposableEffect(lifecycleOwner, uiState.route) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME && uiState.route is AppRoute.Subscribe) {
                viewModel.refreshAccess()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    when (val route = uiState.route) {
        AppRoute.Loading -> SplashRoute()
        AppRoute.Login -> LoginScreen(
            isSupabaseConfigured = uiState.isSupabaseConfigured,
            isSubmitting = uiState.isAuthSubmitting,
            errorMessage = uiState.authErrorMessage,
            onEmailSignIn = viewModel::signInWithEmail,
            onContinue = viewModel::enterDemoMode,
        )
        AppRoute.Onboarding -> OnboardingScreen(
            isSubmitting = uiState.isAuthSubmitting,
            errorMessage = uiState.authErrorMessage,
            onComplete = viewModel::completeOnboarding,
            onPreview = viewModel::activatePreviewWorkspace,
        )
        is AppRoute.Subscribe -> SubscribeScreen(
            memberInactive = route.memberInactive,
            isSubmitting = uiState.isAuthSubmitting,
            isOwner = uiState.authState.role.equals("owner", ignoreCase = true),
            errorMessage = uiState.authErrorMessage,
            onStartMonthlyCheckout = { viewModel.startCheckout("monthly") },
            onStartAnnualCheckout = { viewModel.startCheckout("annual") },
            onContinue = viewModel::enterDemoMode,
        )
        AppRoute.Dashboard -> FlyrDashboard(
            uiState = uiState,
            onSignOut = viewModel::signOut,
        )
    }
}
