package com.selfsurveillance.viewer.data.repository

import com.selfsurveillance.viewer.data.api.SurveillanceApi
import com.selfsurveillance.viewer.data.api.WebSocketClient
import com.selfsurveillance.viewer.data.model.DeviceInfo
import com.selfsurveillance.viewer.data.model.LogEntry
import com.selfsurveillance.viewer.data.model.LogSummary
import com.selfsurveillance.viewer.data.model.ServerConfig
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SurveillanceRepository @Inject constructor(
    private val api: SurveillanceApi,
    private val ws: WebSocketClient,
    private val config: ServerConfig
) {
    suspend fun getSummary(deviceID: String? = null): Result<LogSummary> =
        runCatching { api.getSummary(deviceID) }

    suspend fun getDevices(): Result<List<DeviceInfo>> =
        runCatching { api.getDevices() }

    suspend fun getLogs(
        source: String?   = null,
        category: String? = null,
        deviceID: String? = null,
        date: String?     = null,
        search: String?   = null,
        limit: Int        = 100,
        offset: Int       = 0
    ): Result<List<LogEntry>> = runCatching {
        api.getLogs(source, category, deviceID, date, search, limit, offset)
    }

    fun liveEntries(): Flow<LogEntry> = ws.liveEntries(config.wsLiveUrl)

    fun screenFrames(): Flow<ByteArray> = ws.screenFrames(config.wsScreenUrl)
}
