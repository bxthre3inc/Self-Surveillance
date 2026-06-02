package com.selfsurveillance.viewer.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.selfsurveillance.viewer.data.model.LogEntry
import com.selfsurveillance.viewer.ui.viewmodel.LiveFeedViewModel

private val SOURCES = listOf(
    null, "app_usage", "notifications", "clipboard", "network",
    "packet_flow", "location", "health", "system_events"
)

@Composable
fun LiveFeedScreen(vm: LiveFeedViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Live Feed")
                        // Connection indicator dot
                        Box(
                            Modifier.size(8.dp).background(
                                if (state.isConnected) Color(0xFF64FFDA) else Color.Red,
                                shape = androidx.compose.foundation.shape.CircleShape
                            )
                        )
                    }
                },
                actions = {
                    IconButton(onClick = vm::togglePause) {
                        Icon(
                            if (state.isPaused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                            contentDescription = if (state.isPaused) "Resume" else "Pause"
                        )
                    }
                    IconButton(onClick = vm::clear) {
                        Icon(Icons.Filled.Delete, "Clear")
                    }
                    if (!state.isConnected) {
                        IconButton(onClick = vm::connect) {
                            Icon(Icons.Filled.Wifi, "Connect")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            // Source filter chips
            LazyRow(
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                items(SOURCES) { src ->
                    FilterChip(
                        selected = state.filterSource == src,
                        onClick  = { vm.setSourceFilter(src) },
                        label    = { Text(src?.replace("_", " ")?.replaceFirstChar(Char::uppercase) ?: "All",
                            fontSize = 12.sp) }
                    )
                }
            }

            HorizontalDivider()

            if (state.entries.isEmpty() && !state.isConnected && state.error != null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Not connected", color = MaterialTheme.colorScheme.error)
                        Text(state.error ?: "", style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = vm::connect) { Text("Retry") }
                    }
                }
            } else {
                LazyColumn(
                    reverseLayout = false,
                    contentPadding = PaddingValues(8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    items(state.entries, key = { it.id }) { entry ->
                        LiveEntryRow(entry)
                    }
                }
            }
        }
    }
}

@Composable
private fun LiveEntryRow(entry: LogEntry) {
    val sourceColor = sourceColor(entry.source)
    Card(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top) {
            // Source badge
            Surface(color = sourceColor.copy(alpha = 0.15f),
                shape = MaterialTheme.shapes.small) {
                Text(
                    entry.source.replace("_", "·"),
                    Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                    color = sourceColor, fontSize = 10.sp, fontWeight = FontWeight.Medium
                )
            }
            Column(Modifier.weight(1f)) {
                Text(entry.eventType, style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold)
                entry.appDisplayName?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            // Timestamp (time only)
            Text(entry.timestamp.take(19).takeLast(8),
                fontSize = 10.sp, fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun sourceColor(source: String) = when (source) {
    "app_usage"     -> Color(0xFF64FFDA)
    "notifications" -> Color(0xFF4FC3F7)
    "clipboard"     -> Color(0xFFFFD54F)
    "network"       -> Color(0xFF81C784)
    "packet_flow"   -> Color(0xFFEF9A9A)
    "location"      -> Color(0xFFCE93D8)
    "health"        -> Color(0xFFF48FB1)
    "system_events" -> Color(0xFFFFCC02)
    "dns_query"     -> Color(0xFF80DEEA)
    else            -> Color(0xFF90A4AE)
}
