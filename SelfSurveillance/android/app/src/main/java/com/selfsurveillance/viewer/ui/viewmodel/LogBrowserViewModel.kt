package com.selfsurveillance.viewer.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.selfsurveillance.viewer.data.model.LogEntry
import com.selfsurveillance.viewer.data.repository.SurveillanceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LogBrowserUiState(
    val entries: List<LogEntry>  = emptyList(),
    val isLoading: Boolean       = false,
    val isLoadingMore: Boolean   = false,
    val hasMore: Boolean         = true,
    val error: String?           = null,
    val searchQuery: String      = "",
    val filterSource: String?    = null,
    val filterCategory: String?  = null,
    val filterDate: String?      = null
)

@OptIn(FlowPreview::class)
@HiltViewModel
class LogBrowserViewModel @Inject constructor(
    private val repo: SurveillanceRepository
) : ViewModel() {

    private val _state = MutableStateFlow(LogBrowserUiState(isLoading = true))
    val state: StateFlow<LogBrowserUiState> = _state

    private val pageSize = 50
    private var currentOffset = 0

    // Internal query flow so search debounces before hitting the API
    private val searchFlow = MutableStateFlow("")

    init {
        viewModelScope.launch {
            searchFlow.debounce(400).distinctUntilChanged().collect { query ->
                _state.value = _state.value.copy(searchQuery = query)
                resetAndLoad()
            }
        }
        load()
    }

    fun onSearchChange(query: String) { searchFlow.value = query }

    fun setSource(source: String?)     { _state.value = _state.value.copy(filterSource = source);   resetAndLoad() }
    fun setCategory(cat: String?)      { _state.value = _state.value.copy(filterCategory = cat);    resetAndLoad() }
    fun setDate(date: String?)         { _state.value = _state.value.copy(filterDate = date);        resetAndLoad() }

    fun refresh()    { resetAndLoad() }

    fun loadNextPage() {
        if (_state.value.isLoadingMore || !_state.value.hasMore) return
        load(append = true)
    }

    private fun resetAndLoad() {
        currentOffset = 0
        _state.value  = _state.value.copy(entries = emptyList(), hasMore = true)
        load()
    }

    private fun load(append: Boolean = false) {
        viewModelScope.launch {
            if (append) {
                _state.value = _state.value.copy(isLoadingMore = true)
            } else {
                _state.value = _state.value.copy(isLoading = true, error = null)
            }

            val s = _state.value
            val result = repo.getLogs(
                source   = s.filterSource,
                category = s.filterCategory,
                date     = s.filterDate,
                search   = s.searchQuery.takeIf { it.isNotBlank() },
                limit    = pageSize,
                offset   = currentOffset
            )

            result.fold(
                onSuccess = { newEntries ->
                    currentOffset += newEntries.size
                    val combined = if (append) _state.value.entries + newEntries else newEntries
                    _state.value = _state.value.copy(
                        entries       = combined,
                        isLoading     = false,
                        isLoadingMore = false,
                        hasMore       = newEntries.size == pageSize
                    )
                },
                onFailure = { e ->
                    _state.value = _state.value.copy(
                        isLoading     = false,
                        isLoadingMore = false,
                        error         = e.message
                    )
                }
            )
        }
    }
}
