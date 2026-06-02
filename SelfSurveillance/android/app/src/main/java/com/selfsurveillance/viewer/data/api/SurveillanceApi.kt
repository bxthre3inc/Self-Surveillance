package com.selfsurveillance.viewer.data.api

import com.selfsurveillance.viewer.data.model.DeviceInfo
import com.selfsurveillance.viewer.data.model.LogEntry
import com.selfsurveillance.viewer.data.model.LogSummary
import retrofit2.http.GET
import retrofit2.http.Query

interface SurveillanceApi {

    @GET("api/logs")
    suspend fun getLogs(
        @Query("source")   source: String?  = null,
        @Query("category") category: String? = null,
        @Query("deviceID") deviceID: String? = null,
        @Query("date")     date: String?    = null,
        @Query("search")   search: String?  = null,
        @Query("limit")    limit: Int       = 100,
        @Query("offset")   offset: Int      = 0
    ): List<LogEntry>

    @GET("api/logs/summary")
    suspend fun getSummary(
        @Query("deviceID") deviceID: String? = null
    ): LogSummary

    @GET("api/devices")
    suspend fun getDevices(): List<DeviceInfo>
}
