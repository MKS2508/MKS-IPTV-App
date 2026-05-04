package com.m3u.tv.login

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkQuery
import com.m3u.data.worker.SubscriptionWorker
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

data class TvLoginUiState(
    val name: String = "",
    val serverUrl: String = "",
    val username: String = "",
    val password: String = "",
    val submitting: Boolean = false,
    val errorMessage: String? = null
)

@HiltViewModel
class TvLoginViewModel @Inject constructor(
    private val workManager: WorkManager
) : ViewModel() {
    private val _state = MutableStateFlow(TvLoginUiState())
    val state: StateFlow<TvLoginUiState> = _state.asStateFlow()

    private var pendingTag: String? = null

    init {
        viewModelScope.launch {
            workManager
                .getWorkInfosFlow(WorkQuery.fromTags(SubscriptionWorker.TAG))
                .collect { infos -> reconcile(infos) }
        }
    }

    fun onNameChange(value: String) = _state.update { it.copy(name = value, errorMessage = null) }
    fun onServerUrlChange(value: String) = _state.update { it.copy(serverUrl = value, errorMessage = null) }
    fun onUsernameChange(value: String) = _state.update { it.copy(username = value, errorMessage = null) }
    fun onPasswordChange(value: String) = _state.update { it.copy(password = value, errorMessage = null) }

    fun submit() {
        val s = _state.value
        val error = when {
            s.name.isBlank() -> "Provider name required"
            s.serverUrl.isBlank() -> "Server URL required"
            s.username.isBlank() -> "Username required"
            s.password.isBlank() -> "Password required"
            else -> null
        }
        if (error != null) {
            _state.update { it.copy(errorMessage = error) }
            return
        }
        val basicUrl = normalizeBasicUrl(s.serverUrl) ?: run {
            _state.update { it.copy(errorMessage = "Invalid server URL") }
            return
        }
        pendingTag = basicUrl
        _state.update { it.copy(submitting = true, errorMessage = null) }
        SubscriptionWorker.xtream(
            workManager = workManager,
            title = s.name.trim(),
            url = basicUrl,
            basicUrl = basicUrl,
            username = s.username.trim(),
            password = s.password
        )
    }

    private fun reconcile(infos: List<WorkInfo>) {
        val tag = pendingTag ?: return
        val ours = infos.filter { tag in it.tags }
        if (ours.isEmpty()) return
        if (ours.any { !it.state.isFinished }) return
        val failed = ours.firstOrNull { it.state == WorkInfo.State.FAILED }
        if (failed != null) {
            pendingTag = null
            _state.update { it.copy(submitting = false, errorMessage = "Login failed — check credentials and server URL") }
        } else if (ours.any { it.state == WorkInfo.State.SUCCEEDED }) {
            pendingTag = null
            _state.update { it.copy(submitting = false) }
        }
    }

    private fun normalizeBasicUrl(input: String): String? {
        val trimmed = input.trim().trimEnd('/')
        val withScheme = if (trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true)) trimmed
        else "http://$trimmed"
        val httpUrl = withScheme.toHttpUrlOrNull() ?: return null
        return "${httpUrl.scheme}://${httpUrl.host}:${httpUrl.port}"
    }
}
