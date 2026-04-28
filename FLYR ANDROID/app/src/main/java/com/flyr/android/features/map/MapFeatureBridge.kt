package com.flyr.android.features.map

interface MapFeatureBridge {
    suspend fun warmup()
}

class StubMapFeatureBridge : MapFeatureBridge {
    override suspend fun warmup() = Unit
}

