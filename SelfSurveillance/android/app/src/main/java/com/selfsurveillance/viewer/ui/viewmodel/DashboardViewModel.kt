package com.selfsurveillance.viewer.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.selfsurveillance.viewer.data.model.DeviceInfo
import com.selfsurveillance.viewer.data.model.LogSummary
import com.selfsurveillance.viewer.data.repository.SurveillanceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

data class DashboardUiState(
    val summary: LogSummary?       = null,
    val devices: List<DeviceInfo>  = emptyList(),
    val selectedDeviceID: String?  = null,
    val isLoading: Boolean         = false,
    val error: String?             = null
)

@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val repo: SurveillanceRepository
) : ViewModel() {

    private val _state = MutableStateFlow(DashboardUiState(isLoading = true))
    val state: StateFlow<DashboardUiState> = _state

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isLoading = true, error = null)

            val devicesResult = repo.getDevices()
            val devices = devicesResult.getOrNull() ?: emptyList()

            val summaryResult = repo.getSummary(_state.value.selectedDeviceID)
            _state.value = _state.value.copy(
                isLoading = false,
                devices   = devices,
                summary   = summaryResult.getOrNull(),
                error     = summaryResult.exceptionOrNull()?.message
            )
        }
    }

    fun selectDevice(deviceID: String?) {
        _state.value = _state.value.copy(selectedDeviceID = deviceID)
        refresh()
    }
}
