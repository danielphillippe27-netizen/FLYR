package com.flyr.android.features.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.flyr.android.data.repository.CampaignRepository
import com.flyr.android.data.repository.InMemoryCampaignRepository
import com.flyr.android.features.campaigns.Campaign
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class HomeUiState(
    val isLoading: Boolean = true,
    val campaigns: List<Campaign> = emptyList(),
)

class HomeViewModel : ViewModel() {
    private val campaignRepository: CampaignRepository = InMemoryCampaignRepository()

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val campaigns = campaignRepository.getCampaigns()
            _uiState.update {
                it.copy(
                    isLoading = false,
                    campaigns = campaigns,
                )
            }
        }
    }
}
