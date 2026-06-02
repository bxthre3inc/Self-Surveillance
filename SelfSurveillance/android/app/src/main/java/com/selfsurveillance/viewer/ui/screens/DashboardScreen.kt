package com.selfsurveillance.viewer.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.selfsurveillance.viewer.data.model.DeviceInfo
import com.selfsurveillance.viewer.data.model.LogSummary
import com.selfsurveillance.viewer.ui.viewmodel.DashboardViewModel

@Composable
fun DashboardScreen(vm: DashboardViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Dashboard") },
                actions = {
                    IconButton(onClick = vm::refresh) {
                        Icon(Icons.Filled.Refresh, "Refresh")
                    }
                }
            )
        }
    ) { padding ->
        when {
            state.isLoading -> Box(Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            state.error != null -> ErrorCard(state.error!!, Modifier.padding(padding))
            else -> DashboardContent(
                summary  = state.summary,
                devices  = state.devices,
                selected = state.selectedDeviceID,
                onSelect = vm::selectDevice,
                modifier = Modifier.padding(padding)
            )
        }
    }
}

@Composable
private fun DashboardContent(
    summary: LogSummary?,
    devices: List<DeviceInfo>,
    selected: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {

        // Device selector chips
        if (devices.isNotEmpty()) {
            item {
                Text("Devices", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(6.dp))
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    item {
                        FilterChip(selected = selected == null,
                            onClick = { onSelect(null) }, label = { Text("All") })
                    }
                    items(devices) { dev ->
                        FilterChip(selected = selected == dev.deviceID,
                            onClick = { onSelect(dev.deviceID) },
                            label   = { Text(dev.deviceName) })
                    }
                }
            }
        }

        // Summary stats
        summary?.let { s ->
            item {
                SummaryStatCard("Total Events", s.totalEntries.toString())
            }
            item {
                Text("By Source", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            items(s.bySource.entries.sortedByDescending { it.value }) { (source, count) ->
                SourceRow(source = source, count = count, total = s.totalEntries)
            }
        }
    }
}

@Composable
private fun SummaryStatCard(label: String, value: String) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(value, style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            Text(label, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SourceRow(source: String, count: Long, total: Long) {
    val fraction = if (total > 0) count.toFloat() / total else 0f
    val label = source.replace("_", " ")
        .split(" ").joinToString(" ") { it.replaceFirstChar(Char::uppercase) }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
            Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween) {
                Text(label, style = MaterialTheme.typography.bodyMedium)
                Text(count.toString(), style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.height(4.dp))
            LinearProgressIndicator(
                progress = { fraction },
                modifier = Modifier.fillMaxWidth().height(4.dp),
                color    = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
private fun ErrorCard(message: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Card {
            Text("Error: $message", Modifier.padding(16.dp),
                color = MaterialTheme.colorScheme.error)
        }
    }
}
