package com.flyr.android.core

import com.flyr.android.BuildConfig

object AppConfig {
    val supabaseUrl: String = BuildConfig.SUPABASE_URL.trim()
    val supabaseAnonKey: String = BuildConfig.SUPABASE_ANON_KEY.trim()
    val mapboxPublicToken: String = BuildConfig.MAPBOX_PUBLIC_TOKEN.trim()
    val flyrProApiUrl: String = BuildConfig.FLYR_PRO_API_URL.trim()
    val environment: String = BuildConfig.FLYR_ENVIRONMENT.trim()

    val normalizedFlyrApiUrl: String
        get() = when {
            flyrProApiUrl.isBlank() -> "https://www.flyrpro.app"
            flyrProApiUrl.contains("://flyrpro.app") -> flyrProApiUrl.replace("://flyrpro.app", "://www.flyrpro.app")
            else -> flyrProApiUrl
        }

    val isSupabaseConfigured: Boolean
        get() = supabaseUrl.isNotEmpty() && supabaseAnonKey.isNotEmpty()

    val isMapboxConfigured: Boolean
        get() = mapboxPublicToken.isNotEmpty()
}
