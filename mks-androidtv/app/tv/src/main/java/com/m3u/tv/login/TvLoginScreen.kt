package com.m3u.tv.login

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowForward
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.tv.material3.Icon
import androidx.tv.material3.Text
import com.m3u.tv.TvColors
import com.m3u.tv.TvFonts

@Composable
fun TvLoginScreen(
    viewModel: TvLoginViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val nameFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { nameFocus.requestFocus() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    0f to TvColors.Background,
                    0.6f to TvColors.BackgroundSoft,
                    1f to TvColors.Background
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier
                .widthIn(max = 560.dp)
                .padding(48.dp)
        ) {
            Text(
                text = "Connect to your IPTV provider",
                color = TvColors.TextPrimary,
                fontSize = 38.sp,
                lineHeight = 44.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = TvFonts.Body
            )
            Text(
                text = "Enter your Xtream Codes credentials. We'll fetch live channels, movies and series automatically.",
                color = TvColors.TextSecondary,
                fontSize = 16.sp,
                lineHeight = 22.sp,
                fontFamily = TvFonts.Body
            )

            LoginField(
                label = "Provider name",
                value = state.name,
                onValueChange = viewModel::onNameChange,
                placeholder = "Home, Backup, …",
                imeAction = ImeAction.Next,
                modifier = Modifier.focusRequester(nameFocus)
            )
            LoginField(
                label = "Server URL",
                value = state.serverUrl,
                onValueChange = viewModel::onServerUrlChange,
                placeholder = "http://server.example.com:8080",
                imeAction = ImeAction.Next,
                keyboardType = KeyboardType.Uri
            )
            LoginField(
                label = "Username",
                value = state.username,
                onValueChange = viewModel::onUsernameChange,
                placeholder = "your_username",
                imeAction = ImeAction.Next
            )
            LoginField(
                label = "Password",
                value = state.password,
                onValueChange = viewModel::onPasswordChange,
                placeholder = "your_password",
                imeAction = ImeAction.Done,
                keyboardType = KeyboardType.Password,
                masked = true,
                onImeDone = viewModel::submit
            )

            AnimatedVisibility(
                visible = state.errorMessage != null,
                enter = fadeIn(),
                exit = fadeOut()
            ) {
                Text(
                    text = state.errorMessage.orEmpty(),
                    color = Color(0xFFFF6B6B),
                    fontSize = 14.sp,
                    fontFamily = TvFonts.Body
                )
            }

            SubmitButton(
                submitting = state.submitting,
                onClick = viewModel::submit
            )
        }
    }
}

@Composable
private fun LoginField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    imeAction: ImeAction,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
    masked: Boolean = false,
    onImeDone: (() -> Unit)? = null
) {
    var focused by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = label,
            color = if (focused) TvColors.TextPrimary else TvColors.TextSecondary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = TvFonts.Body
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(TvColors.Surface.copy(alpha = if (focused) 0.96f else 0.86f))
                .border(
                    BorderStroke(
                        width = if (focused) 2.dp else 1.dp,
                        color = if (focused) TvColors.Focus else Color.White.copy(alpha = 0.08f)
                    ),
                    RoundedCornerShape(12.dp)
                )
                .padding(horizontal = 16.dp),
            contentAlignment = Alignment.CenterStart
        ) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                cursorBrush = SolidColor(TvColors.Focus),
                visualTransformation = if (masked) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
                keyboardOptions = KeyboardOptions(
                    keyboardType = keyboardType,
                    imeAction = imeAction
                ),
                keyboardActions = KeyboardActions(
                    onDone = { onImeDone?.invoke() }
                ),
                textStyle = androidx.compose.ui.text.TextStyle(
                    color = TvColors.TextPrimary,
                    fontSize = 17.sp,
                    fontFamily = TvFonts.Body
                ),
                modifier = modifier
                    .fillMaxWidth()
                    .onFocusChanged { focused = it.isFocused }
            )
            if (value.isEmpty() && !focused) {
                Text(
                    text = placeholder,
                    color = TvColors.TextSecondary.copy(alpha = 0.5f),
                    fontSize = 17.sp,
                    fontFamily = TvFonts.Body
                )
            }
        }
    }
}

@Composable
private fun SubmitButton(
    submitting: Boolean,
    onClick: () -> Unit
) {
    var focused by remember { mutableStateOf(false) }
    val label = if (submitting) "Connecting…" else "Connect"
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(if (focused) TvColors.Focus else TvColors.Surface.copy(alpha = 0.92f))
            .border(
                BorderStroke(
                    width = if (focused) 3.dp else 1.dp,
                    color = if (focused) Color.White else Color.White.copy(alpha = 0.10f)
                ),
                RoundedCornerShape(12.dp)
            )
            .focusable(enabled = !submitting)
            .onFocusChanged { focused = it.isFocused }
            .onKeyEvent { event ->
                if (event.type == KeyEventType.KeyUp &&
                    (event.key == Key.Enter || event.key == Key.DirectionCenter || event.key == Key.NumPadEnter)
                ) {
                    if (!submitting) onClick()
                    true
                } else false
            },
        contentAlignment = Alignment.Center
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = label,
                color = if (focused) TvColors.OnFocus else TvColors.TextPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = TvFonts.Body
            )
            if (!submitting) {
                Icon(
                    imageVector = Icons.Rounded.ArrowForward,
                    contentDescription = null,
                    tint = if (focused) TvColors.OnFocus else TvColors.TextPrimary,
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}
