package com.flyr.android.app

sealed interface AppRoute {
    data object Loading : AppRoute
    data object Login : AppRoute
    data object Onboarding : AppRoute
    data class Subscribe(
        val memberInactive: Boolean = false,
    ) : AppRoute
    data object Dashboard : AppRoute
}
