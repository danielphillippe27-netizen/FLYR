package com.flyr.android.data.repository

import com.flyr.android.features.campaigns.Campaign

interface CampaignRepository {
    suspend fun getCampaigns(): List<Campaign>
}

class InMemoryCampaignRepository : CampaignRepository {
    override suspend fun getCampaigns(): List<Campaign> {
        return listOf(
            Campaign(id = "demo-1", name = "Demo Campaign", territoryName = "North Block"),
        )
    }
}

