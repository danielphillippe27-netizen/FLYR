package com.flyr.android.data.services

interface MapService {
    suspend fun initialize()
}

class StubMapService : MapService {
    override suspend fun initialize() = Unit
}

