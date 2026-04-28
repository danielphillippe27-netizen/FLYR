package com.flyr.android.data.services

import com.flyr.android.features.stats.LeaderboardEntry
import com.flyr.android.features.stats.UserStats

interface StatsService {
    suspend fun getUserStats(): UserStats
    suspend fun getLeaderboard(): List<LeaderboardEntry>
}

class StubStatsService : StatsService {
    override suspend fun getUserStats(): UserStats = UserStats()

    override suspend fun getLeaderboard(): List<LeaderboardEntry> {
        return listOf(
            LeaderboardEntry(userName = "You", score = 0),
        )
    }
}
