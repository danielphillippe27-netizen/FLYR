package com.flyr.android.navigation

import com.flyr.android.app.RootUiState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.flyr.android.features.home.HomeScreen
import com.flyr.android.features.leaderboard.LeaderboardScreen
import com.flyr.android.features.leads.LeadsScreen
import com.flyr.android.features.record.RecordScreen
import com.flyr.android.features.settings.SettingsScreen

@Composable
fun FlyrNavHost(
    navController: NavHostController,
    modifier: Modifier = Modifier,
    rootUiState: RootUiState,
    onSignOut: () -> Unit,
) {
    NavHost(
        navController = navController,
        startDestination = FlyrDestination.Home.route,
        modifier = modifier,
    ) {
        composable(FlyrDestination.Home.route) {
            HomeScreen()
        }
        composable(FlyrDestination.Record.route) {
            RecordScreen()
        }
        composable(FlyrDestination.Leads.route) {
            LeadsScreen()
        }
        composable(FlyrDestination.Leaderboard.route) {
            LeaderboardScreen()
        }
        composable(FlyrDestination.Settings.route) {
            SettingsScreen(
                uiState = rootUiState,
                onSignOut = onSignOut,
            )
        }
    }
}
