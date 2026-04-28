package com.flyr.android.features.stats

data class UserStats(
    val flyersDelivered: Int = 0,
    val homesVisited: Int = 0,
    val sessionsCompleted: Int = 0,
)

data class LeaderboardEntry(
    val userName: String,
    val score: Int,
)

