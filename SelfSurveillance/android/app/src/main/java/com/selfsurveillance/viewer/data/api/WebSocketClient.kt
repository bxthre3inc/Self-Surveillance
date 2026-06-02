package com.selfsurveillance.viewer.data.api

import com.google.gson.Gson
import com.selfsurveillance.viewer.data.model.LogEntry
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class WebSocketClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val gson: Gson
) {
    // Returns a cold Flow of live LogEntry events from the /live WebSocket.
    // The connection is opened when the flow is collected and closed when cancelled.
    fun liveEntries(url: String): Flow<LogEntry> = callbackFlow {
        val request = Request.Builder().url(url).build()
        val ws = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching { gson.fromJson(text, LogEntry::class.java) }
                    .onSuccess { trySend(it) }
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                close(t)
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                close()
            }
        })
        awaitClose { ws.close(1000, "cancelled") }
    }

    // Returns a cold Flow of raw JPEG byte arrays from the /screen/watch WebSocket.
    fun screenFrames(url: String): Flow<ByteArray> = callbackFlow {
        val request = Request.Builder().url(url).build()
        val ws = okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                trySend(bytes.toByteArray())
            }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                close(t)
            }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                close()
            }
        })
        awaitClose { ws.close(1000, "cancelled") }
    }
}
