package com.flyr.android.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import com.flyr.android.designsystem.theme.FlyrTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppServices.initialize(applicationContext)
        enableEdgeToEdge()
        setContent {
            FlyrTheme {
                val appViewModel: FlyrAppViewModel = viewModel()
                AuthGate(viewModel = appViewModel)
            }
        }
    }
}
