package com.m3u.tv.login

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import com.m3u.data.database.model.DataSource
import com.m3u.data.repository.playlist.PlaylistRepository
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.m3u.tv.TvColors
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Composable
fun LoginGate(
    content: @Composable () -> Unit,
    viewModel: LoginGateViewModel = hiltViewModel()
) {
    val hasXtreamProfile by viewModel.hasXtreamProfile.collectAsStateWithLifecycle(initialValue = null)
    when (hasXtreamProfile) {
        null -> Box(Modifier.fillMaxSize().background(TvColors.Background))
        false -> TvLoginScreen()
        true -> content()
    }
}

@HiltViewModel
class LoginGateViewModel @Inject constructor(
    playlistRepository: PlaylistRepository
) : ViewModel() {
    val hasXtreamProfile: Flow<Boolean> = playlistRepository.observeAll()
        .map { playlists -> playlists.any { it.source == DataSource.Xtream } }
}
