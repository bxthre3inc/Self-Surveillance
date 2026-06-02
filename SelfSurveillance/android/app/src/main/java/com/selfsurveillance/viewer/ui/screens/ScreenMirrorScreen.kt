package com.selfsurveillance.viewer.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.selfsurveillance.viewer.ui.viewmodel.ScreenMirrorViewModel

@Composable
fun ScreenMirrorScreen(vm: ScreenMirrorViewModel = hiltViewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Screen Mirror")
                        // Live indicator
                        if (state.isConnected) {
                            Surface(color = Color.Red, shape = CircleShape) {
                                Text("LIVE", Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                    color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                },
                actions = {
                    // FPS counter
                    if (state.isConnected) {
                        Text("${state.fps.toInt()} fps",
                            Modifier.padding(end = 8.dp),
                            fontFamily = FontFamily.Monospace, fontSize = 12.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (!state.isConnected) {
                        IconButton(onClick = vm::connect) {
                            Icon(Icons.Filled.Wifi, "Connect")
                        }
                    } else {
                        IconButton(onClick = vm::disconnect) {
                            Icon(Icons.Filled.WifiOff, "Disconnect")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).background(Color.Black)) {

            // Main screen view — fills available space
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .background(Color(0xFF0D1117)),
                contentAlignment = Alignment.Center
            ) {
                when {
                    state.currentFrame != null -> {
                        Image(
                            bitmap = state.currentFrame!!.asImageBitmap(),
                            contentDescription = "iPhone screen",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Fit
                        )
                        // Recording overlay badge
                        if (state.isRecording) {
                            Row(
                                Modifier
                                    .align(Alignment.TopEnd)
                                    .padding(12.dp)
                                    .background(Color.Red.copy(alpha = 0.85f),
                                        MaterialTheme.shapes.small)
                                    .padding(horizontal = 8.dp, vertical = 4.dp),
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(Modifier.size(6.dp).background(Color.White, CircleShape))
                                Text("REC", color = Color.White, fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                    !state.isConnected -> {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Filled.PhoneIphone, null,
                                Modifier.size(64.dp), tint = Color.Gray)
                            Spacer(Modifier.height(12.dp))
                            Text("Not connected to iPhone", color = Color.Gray)
                            if (state.error != null) {
                                Text(state.error!!, color = Color(0xFFFF5370), fontSize = 12.sp)
                            }
                            Spacer(Modifier.height(16.dp))
                            Button(onClick = vm::connect) {
                                Icon(Icons.Filled.Wifi, null)
                                Spacer(Modifier.width(8.dp))
                                Text("Connect")
                            }
                        }
                    }
                    else -> CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            // Control bar
            Surface(color = MaterialTheme.colorScheme.surface) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Frame counter
                    Column {
                        Text("Frames received", style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(state.frameCount.toString(),
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurface)
                    }

                    // Record button
                    when {
                        state.isRecording -> {
                            ExtendedFloatingActionButton(
                                onClick          = vm::stopRecording,
                                containerColor   = MaterialTheme.colorScheme.errorContainer,
                                contentColor     = MaterialTheme.colorScheme.error,
                                icon             = { Icon(Icons.Filled.Stop, "Stop") },
                                text             = { Text("Stop Recording") }
                            )
                        }
                        state.isConnected -> {
                            ExtendedFloatingActionButton(
                                onClick          = vm::startRecording,
                                containerColor   = Color.Red,
                                contentColor     = Color.White,
                                icon             = { Icon(Icons.Filled.FiberManualRecord, "Record") },
                                text             = { Text("Record") }
                            )
                        }
                        else -> {
                            ExtendedFloatingActionButton(
                                onClick          = vm::connect,
                                icon             = { Icon(Icons.Filled.Wifi, "Connect") },
                                text             = { Text("Connect") }
                            )
                        }
                    }

                    // Save path indicator
                    state.recordingPath?.let { path ->
                        Column(horizontalAlignment = Alignment.End) {
                            Text("Last saved", style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(path.substringAfterLast("/"), fontSize = 10.sp,
                                fontFamily = FontFamily.Monospace,
                                color = MaterialTheme.colorScheme.primary)
                        }
                    } ?: Spacer(Modifier.width(80.dp))
                }
            }
        }
    }
}
