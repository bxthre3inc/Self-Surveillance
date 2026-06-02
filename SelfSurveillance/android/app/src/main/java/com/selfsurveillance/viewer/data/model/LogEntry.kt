package com.selfsurveillance.viewer.data.model

import com.google.gson.JsonObject

data class LogEntry(
    val id: String,
    val timestamp: String,
    val deviceID: String,
    val deviceName: String,
    val iOSVersion: String,
    val source: String,
    val category: String,
    val appBundleID: String?,
    val appDisplayName: String?,
    val eventType: String,
    val payload: JsonObject?,
    val sequenceNumber: Long,
    val previousEntryHash: String
) {
    val sourceLabel: String get() = source.replace("_", " ")
        .split(" ").joinToString(" ") { it.replaceFirstChar(Char::uppercase) }

    val categoryLabel: String get() = category
}

data class LogSummary(
    val totalEntries: Long,
    val bySource: Map<String, Long>,
    val byCategory: Map<String, Long>,
    val devices: List<DeviceInfo>,
    val oldestTimestamp: String?,
    val newestTimestamp: String?
)

data class DeviceInfo(
    val deviceID: String,
    val deviceName: String,
    val iOSVersion: String,
    val lastSeen: String,
    val entryCount: Long
)

data class ServerConfig(
    val host: String,
    val port: Int
) {
    val baseUrl: String get() = "http://$host:$port/"
    val wsLiveUrl: String get() = "ws://$host:$port/live"
    val wsScreenUrl: String get() = "ws://$host:$port/screen/watch"
}
