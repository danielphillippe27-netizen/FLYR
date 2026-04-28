package com.flyr.android.features.leaderboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flyr.android.data.services.StatsService
import com.flyr.android.data.services.StubStatsService
import com.flyr.android.features.stats.LeaderboardEntry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class LeaderboardUiState(
    val entries: List<LeaderboardEntry> = emptyList(),
)

class LeaderboardViewModel : ViewModel() {
    private val statsService: StatsService = StubStatsService()

    private val _uiState = MutableStateFlow(LeaderboardUiState())
    val uiState: StateFlow<LeaderboardUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            _uiState.update {
                it.copy(entries = statsService.getLeaderboard())
            }
        }
    }
}
