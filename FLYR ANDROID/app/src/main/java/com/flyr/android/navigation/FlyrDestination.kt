package com.flyr.android.navigation

sealed class FlyrDestination(
    val route: String,
    val label: String,
) {
    data object Home : FlyrDestination("home", "Home")
    data object Record : FlyrDestination("record", "Record")
    data object Leads : FlyrDestination("leads", "Leads")
    data object Leaderboard : FlyrDestination("leaderboard", "Leaderboard")
    data object Settings : FlyrDestination("settings", "Settings")
}

