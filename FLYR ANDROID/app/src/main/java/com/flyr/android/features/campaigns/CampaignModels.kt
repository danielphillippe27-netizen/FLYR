package com.flyr.android.features.campaigns

data class Campaign(
    val id: String,
    val name: String,
    val territoryName: String? = null,
)

data class CampaignContext(
    val activeCampaign: Campaign? = null,
    val accentHex: String = "#1677FF",
)

