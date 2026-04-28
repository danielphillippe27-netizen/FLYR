package com.flyr.android.app

import android.content.Context
import com.flyr.android.core.AppConfig
import com.flyr.android.data.services.AccessRouterService
import com.flyr.android.data.services.AccessService
import com.flyr.android.data.services.AuthService
import io.github.jan.supabase.SupabaseClient
import com.flyr.android.data.services.DefaultAccessRouterService
import com.flyr.android.data.services.DefaultAccessService
import com.flyr.android.data.services.SharedPrefsAuthService
import com.flyr.android.data.services.SupabaseAuthService
import com.flyr.android.data.services.createFlyrSupabaseClient
import com.flyr.android.data.storage.SessionStorage

object AppServices {
    private var initialized = false

    lateinit var sessionStorage: SessionStorage
        private set

    lateinit var authService: AuthService
        private set

    var supabaseClient: SupabaseClient? = null
        private set

    lateinit var accessRouterService: AccessRouterService
        private set

    lateinit var accessService: AccessService
        private set

    fun initialize(context: Context) {
        if (initialized) return

        sessionStorage = SessionStorage(context.applicationContext)
        supabaseClient = if (AppConfig.isSupabaseConfigured) {
            createFlyrSupabaseClient()
        } else {
            null
        }
        authService = if (supabaseClient != null) {
            SupabaseAuthService(
                sessionStorage = sessionStorage,
                client = checkNotNull(supabaseClient),
            )
        } else {
            SharedPrefsAuthService(sessionStorage)
        }
        accessRouterService = DefaultAccessRouterService()
        accessService = DefaultAccessService(
            sessionStorage = sessionStorage,
            fallbackRouterService = accessRouterService,
            supabaseClient = supabaseClient,
        )
        initialized = true
    }
}
