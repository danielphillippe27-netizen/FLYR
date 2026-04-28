package com.flyr.android.app

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Leaderboard
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.flyr.android.navigation.FlyrDestination
import com.flyr.android.navigation.FlyrNavHost

@Composable
fun FlyrAndroidApp(
    rootUiState: RootUiState,
    onSignOut: () -> Unit,
) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val topLevelDestinations = listOf(
        FlyrDestination.Home,
        FlyrDestination.Record,
        FlyrDestination.Leads,
        FlyrDestination.Leaderboard,
        FlyrDestination.Settings,
    )

    Scaffold(
        bottomBar = {
            NavigationBar {
                topLevelDestinations.forEach { destination ->
                    NavigationBarItem(
                        selected = currentRoute == destination.route,
                        onClick = {
                            navController.navigate(destination.route) {
                                popUpTo(navController.graph.startDestinationId) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            Icon(
                                imageVector = when (destination) {
                                    FlyrDestination.Home -> Icons.Filled.Home
                                    FlyrDestination.Record -> Icons.Filled.PlayArrow
                                    FlyrDestination.Leads -> Icons.AutoMirrored.Filled.List
                                    FlyrDestination.Leaderboard -> Icons.Filled.Leaderboard
                                    FlyrDestination.Settings -> Icons.Filled.Settings
                                },
                                contentDescription = destination.label,
                            )
                        },
                        label = {
                            Text(destination.label)
                        },
                    )
                }
            }
        },
    ) { innerPadding ->
        FlyrNavHost(
            navController = navController,
            modifier = Modifier.padding(innerPadding),
            rootUiState = rootUiState,
            onSignOut = onSignOut,
        )
    }
}
