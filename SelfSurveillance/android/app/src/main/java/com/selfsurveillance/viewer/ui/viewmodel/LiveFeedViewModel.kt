package com.selfsurveillance.viewer.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.selfsurveillance.viewer.data.model.LogEntry
import com.selfsurveillance.viewer.data.repository.SurveillanceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LiveFeedUiState(
    val entries: List<LogEntry>   = emptyList(),
    val isConnected: Boolean      = false,
    val error: String?            = null,
    val filterSource: String?     = null,
    val isPaused: Boolean         = false
)

@HiltViewModel
class LiveFeedViewModel @Inject constructor(
    private val repo: SurveillanceRepository
) : ViewModel() {

    private val _state = MutableStateFlow(LiveFeedUiState())
    val state: StateFlow<LiveFeedUiState> = _state

    // Keep at most 500 entries in memory
    private val maxEntries = 500
    private var collectJob: Job? = null

    init { connect() }

    fun connect() {
        collectJob?.cancel()
        collectJob = viewModelScope.launch {
            _state.value = _state.value.copy(isConnected = false, error = null)
            repo.liveEntries()
                .catch { e -> _state.value = _state.value.copy(error = e.message, isConnected = false) }
                .collect { entry ->
                    if (_state.value.isPaused) return@collect
                    val src = _state.value.filterSource
                    if (src != null && entry.source != src) return@collect
                    val updated = (listOf(entry) + _state.value.entries).take(maxEntries)
                    _state.value = _state.value.copy(entries = updated, isConnected = true)
                }
        }
    }

    fun disconnect() {
        collectJob?.cancel()
        _state.value = _state.value.copy(isConnected = false)
    }

    fun togglePause() {
        _state.value = _state.value.copy(isPaused = !_state.value.isPaused)
    }

    fun setSourceFilter(source: String?) {
        _state.value = _state.value.copy(filterSource = source)
    }

    fun clear() {
        _state.value = _state.value.copy(entries = emptyList())
    }

    override fun onCleared() {
        super.onCleared()
        collectJob?.cancel()
    }
}
