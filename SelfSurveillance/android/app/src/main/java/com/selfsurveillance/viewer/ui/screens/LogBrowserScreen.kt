package com.selfsurveillance.viewer.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.selfsurveillance.viewer.data.model.LogEntry
import com.selfsurveillance.viewer.ui.viewmodel.LogBrowserViewModel

private val ALL_SOURCES = listOf(
    "app_usage", "notifications", "clipboard", "photo_library", "contacts",
    "calendar", "health", "location", "network", "packet_flow", "dns_query",
    "bluetooth", "wifi", "system_events", "files", "notes", "keychain"
)

@Composable
fun LogBrowserScreen(vm: LogBrowserViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    var detailEntry by remember { mutableStateOf<LogEntry?>(null) }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(title = { Text("Log Browser") })
                // Search bar
                OutlinedTextField(
                    value = state.searchQuery,
                    onValueChange = vm::onSearchChange,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                    placeholder = { Text("Search events…") },
                    leadingIcon  = { Icon(Icons.Filled.Search, null) },
                    trailingIcon = {
                        if (state.searchQuery.isNotEmpty()) {
                            IconButton(onClick = { vm.onSearchChange("") }) {
                                Icon(Icons.Filled.Close, "Clear")
                            }
                        }
                    },
                    singleLine = true
                )
                // Source filter chips
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    item {
                        FilterChip(selected = state.filterSource == null,
                            onClick = { vm.setSource(null) }, label = { Text("All", fontSize = 12.sp) })
                    }
                    items(ALL_SOURCES) { src ->
                        FilterChip(
                            selected = state.filterSource == src,
                            onClick  = { vm.setSource(if (state.filterSource == src) null else src) },
                            label    = { Text(src.replace("_", " ").take(12), fontSize = 11.sp) }
                        )
                    }
                }
                HorizontalDivider()
            }
        }
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                state.isLoading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                state.error != null -> Column(Modifier.align(Alignment.Center),
                    horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Error: ${state.error}", color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = vm::refresh) { Text("Retry") }
                }
                state.entries.isEmpty() -> Text("No logs found",
                    Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                else -> {
                    val listState = rememberLazyListState()
                    LazyColumn(state = listState,
                        contentPadding = PaddingValues(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        items(state.entries, key = { it.id }) { entry ->
                            LogEntryRow(entry, onClick = { detailEntry = entry })
                        }
                        if (state.isLoadingMore) {
                            item {
                                Box(Modifier.fillMaxWidth().padding(16.dp),
                                    contentAlignment = Alignment.Center) {
                                    CircularProgressIndicator(Modifier.size(24.dp))
                                }
                            }
                        }
                    }

                    // Trigger pagination near the bottom
                    val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
                    LaunchedEffect(lastVisible) {
                        if (lastVisible >= state.entries.size - 10) {
                            vm.loadNextPage()
                        }
                    }
                }
            }
        }
    }

    detailEntry?.let { entry ->
        LogDetailDialog(entry = entry, onDismiss = { detailEntry = null })
    }
}

@Composable
private fun LogEntryRow(entry: LogEntry, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(entry.eventType, style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold)
                    Text("·", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(entry.source.replace("_", " "), fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.primary)
                }
                entry.appDisplayName?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(entry.timestamp.replace("T", " ").take(19),
                    fontSize = 10.sp, fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text("#${entry.sequenceNumber}", fontSize = 10.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun LogDetailDialog(entry: LogEntry, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss) {
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp).heightIn(max = 500.dp)) {
                Text(entry.eventType, style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold)
                Text(entry.source.replace("_", " ") + "  ·  " + entry.category,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                HorizontalDivider(Modifier.padding(vertical = 8.dp))

                LazyColumn {
                    item { DetailRow("Timestamp",   entry.timestamp) }
                    item { DetailRow("Device",      "${entry.deviceName} (${entry.iOSVersion})") }
                    item { DetailRow("Sequence",    entry.sequenceNumber.toString()) }
                    entry.appBundleID?.let { item { DetailRow("App",    it) } }
                    item {
                        Text("Payload", style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 8.dp, bottom = 4.dp))
                        Surface(color = MaterialTheme.colorScheme.surfaceVariant,
                            shape = MaterialTheme.shapes.small) {
                            Text(
                                entry.payload?.toString()?.let { prettyJson(it) } ?: "(empty)",
                                Modifier.padding(8.dp).fillMaxWidth(),
                                fontFamily = FontFamily.Monospace, fontSize = 11.sp
                            )
                        }
                    }
                }

                Spacer(Modifier.height(12.dp))
                TextButton(onClick = onDismiss, Modifier.align(Alignment.End)) { Text("Close") }
            }
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.width(80.dp))
        Text(value, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
    }
}

private fun prettyJson(raw: String): String = raw
    .replace("{", "{\n  ")
    .replace("}", "\n}")
    .replace(",", ",\n  ")
