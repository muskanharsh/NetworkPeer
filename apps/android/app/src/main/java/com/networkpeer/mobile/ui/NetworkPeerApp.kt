package com.networkpeer.mobile.ui

import android.content.Context
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ArrowForward
import androidx.compose.material.icons.outlined.BusinessCenter
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Engineering
import androidx.compose.material.icons.outlined.FlashOn
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.outlined.Work
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.draw.clip
import com.networkpeer.mobile.core.model.UpdateProfileBody
import com.networkpeer.mobile.core.model.AuthUser
import com.networkpeer.mobile.core.model.StoredSession
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.networkpeer.mobile.AppContainer
import com.networkpeer.mobile.R
import com.networkpeer.mobile.core.model.JobStatus
import com.networkpeer.mobile.core.model.NetworkPeerApiException
import com.networkpeer.mobile.core.model.UserRole
import com.networkpeer.mobile.ui.theme.BrandSkyContainer
import com.networkpeer.mobile.ui.theme.BrandSkyLight
import com.networkpeer.mobile.ui.theme.BrandSkyPrimary
import com.networkpeer.mobile.ui.theme.BrandSkySoft
import com.networkpeer.mobile.ui.theme.BrandSkyText
import com.networkpeer.mobile.ui.theme.BrandSkyVibrant
import com.networkpeer.mobile.ui.theme.BrandTeal
import com.networkpeer.mobile.ui.theme.Danger
import com.networkpeer.mobile.ui.theme.Slate400
import com.networkpeer.mobile.ui.theme.Success
import com.networkpeer.mobile.ui.theme.Warning
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

@Composable
fun NetworkPeerApp(container: AppContainer) {
    val session by container.client.sessionStore.session.collectAsState()
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        when {
            !container.client.configuration.apiConfigured -> MissingConfigurationScreen()
            session == null -> AuthScreen(container)
            else -> {
                val activeSession = requireNotNull(session)
                key(activeSession.user.id, activeSession.user.role) {
                    ReleaseAuthenticatedApp(container, activeSession)
                }
            }
        }
    }
}

@Composable
private fun MissingConfigurationScreen() {
    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        BrandMark()
        Spacer(Modifier.height(28.dp))
        Text(
            stringResource(R.string.configuration_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(12.dp))
        Text(
            stringResource(R.string.configuration_body),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(18.dp))
        InlineNotice(stringResource(R.string.configuration_api_label), BrandSkyPrimary)
    }
}

@Composable
private fun RoleSelectionCard(
    modifier: Modifier = Modifier,
    title: String,
    description: String,
    selected: Boolean,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    val isDark = isSystemInDarkTheme()
    val cardBg = if (selected) {
        if (isDark) Color(0xFFF9C933).copy(alpha = 0.2f) else Color(0xFFFEF9C3)
    } else {
        MaterialTheme.colorScheme.surface
    }
    val cardBorder = if (selected) Color(0xFFF9C933) else MaterialTheme.colorScheme.outline
    val iconBg = if (selected) {
        Color(0xFFF9C933)
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    val iconTint = if (selected) {
        Color(0xFF111827)
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val titleColor = if (selected) {
        if (isDark) Color.White else Color(0xFF111827)
    } else {
        MaterialTheme.colorScheme.onSurface
    }
    val descColor = MaterialTheme.colorScheme.onSurfaceVariant

    Surface(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        color = cardBg,
        border = BorderStroke(
            width = if (selected) 2.dp else 1.dp,
            color = cardBorder,
        ),
        shadowElevation = if (selected) 2.dp else 0.dp,
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .background(
                            color = iconBg,
                            shape = RoundedCornerShape(10.dp),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = iconTint,
                        modifier = Modifier.size(20.dp),
                    )
                }
                if (selected) {
                    Box(
                        modifier = Modifier
                            .size(20.dp)
                            .background(Color(0xFFF9C933), RoundedCornerShape(10.dp)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Check,
                            contentDescription = null,
                            tint = Color(0xFF111827),
                            modifier = Modifier.size(14.dp),
                        )
                    }
                }
            }
            Spacer(Modifier.height(2.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = titleColor,
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall,
                color = descColor,
            )
        }
    }
}

@Composable
private fun AuthScreen(container: AppContainer) {
    val context = LocalContext.current
    var isRegisterMode by rememberSaveable { mutableStateOf(false) }
    var fullName by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var phone by rememberSaveable { mutableStateOf("") }
    var otp by rememberSaveable { mutableStateOf("") }
    var roleName by rememberSaveable { mutableStateOf(UserRole.WORKER.name) }
    var otpRequested by rememberSaveable { mutableStateOf(false) }
    var challengeId by rememberSaveable { mutableStateOf("") }
    var deliveryNote by rememberSaveable { mutableStateOf<String?>(null) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val role = UserRole.valueOf(roleName)

    fun resetOtpRequest() {
        otpRequested = false
        otp = ""
        challengeId = ""
        deliveryNote = null
        error = null
    }

    // Normalizes input to E.164 (+91XXXXXXXXXX) format expected by server
    fun normalizePhone(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.startsWith("+")) {
            return "+" + trimmed.substring(1).filter(Char::isDigit)
        }
        val digits = trimmed.filter(Char::isDigit)
        return when {
            digits.length == 10 -> "+91$digits"
            digits.length == 12 && digits.startsWith("91") -> "+$digits"
            digits.length == 11 && digits.startsWith("1") -> "+$digits"
            else -> "+$digits"
        }
    }

    suspend fun requestCode() {
        if (isRegisterMode) {
            if (fullName.trim().length < 2) {
                error = context.getString(R.string.full_name_required)
                return
            }
            val rawDigits = phone.filter(Char::isDigit)
            if (rawDigits.length < 10 && !phone.trim().startsWith("+")) {
                error = context.getString(R.string.phone_invalid_error)
                return
            }
        }

        val trimmedEmail = email.trim().lowercase()
        if (trimmedEmail.isBlank() || !android.util.Patterns.EMAIL_ADDRESS.matcher(trimmedEmail).matches()) {
            error = context.getString(R.string.email_invalid_error)
            return
        }

        val normalizedPhone = if (phone.isNotBlank()) normalizePhone(phone) else ""
        val result = container.authRepository.requestEmailOtp(
            email = trimmedEmail,
            role = role,
            fullName = if (isRegisterMode) fullName.trim() else null,
            mobileNumber = if (isRegisterMode) normalizedPhone else null,
        )
        otpRequested = true
        challengeId = result.challengeId
        otp = ""
        deliveryNote = if (result.message.isNotBlank()) result.message else "Verification code dispatched to $trimmedEmail."
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 24.dp, vertical = 32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            val themeMode by container.themeMode.collectAsState()
            val systemInDark = isSystemInDarkTheme()
            val isDark = when (themeMode) {
                "dark" -> true
                "light" -> false
                else -> systemInDark
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                BrandMark()
                IconButton(onClick = { container.toggleTheme(systemInDark) }) {
                    Icon(
                        imageVector = if (isDark) Icons.Outlined.LightMode else Icons.Outlined.DarkMode,
                        contentDescription = if (isDark) "Switch to Light Mode" else "Switch to Dark Mode",
                        tint = if (isDark) BrandSkyLight else BrandSkyPrimary,
                    )
                }
            }
            Spacer(Modifier.height(16.dp))

            Text(
                text = if (isRegisterMode) stringResource(R.string.register_title) else stringResource(R.string.sign_in_title),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = if (isRegisterMode) stringResource(R.string.register_subtitle) else stringResource(R.string.sign_in_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        item {
            Card(
                shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
            ) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    TabRow(
                        selectedTabIndex = if (isRegisterMode) 0 else 1,
                        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                        modifier = Modifier.clip(RoundedCornerShape(12.dp)),
                    ) {
                        Tab(
                            selected = isRegisterMode,
                            onClick = { if (!isRegisterMode) { isRegisterMode = true; resetOtpRequest() } },
                            text = { Text(stringResource(R.string.register_tab), fontWeight = FontWeight.SemiBold) },
                        )
                        Tab(
                            selected = !isRegisterMode,
                            onClick = { if (isRegisterMode) { isRegisterMode = false; resetOtpRequest() } },
                            text = { Text(stringResource(R.string.sign_in_tab), fontWeight = FontWeight.SemiBold) },
                        )
                    }

                    Text(
                        text = stringResource(R.string.role_prompt),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        RoleSelectionCard(
                            modifier = Modifier.weight(1f),
                            title = stringResource(R.string.client),
                            description = stringResource(R.string.role_client_desc),
                            selected = role == UserRole.CLIENT,
                            icon = Icons.Outlined.BusinessCenter,
                            onClick = { roleName = UserRole.CLIENT.name },
                        )
                        RoleSelectionCard(
                            modifier = Modifier.weight(1f),
                            title = stringResource(R.string.worker),
                            description = stringResource(R.string.role_worker_desc),
                            selected = role == UserRole.WORKER,
                            icon = Icons.Outlined.Engineering,
                            onClick = { roleName = UserRole.WORKER.name },
                        )
                    }

                    // Quick Instant Demo Login for Testing
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        OutlinedButton(
                            onClick = {
                                scope.launch {
                                    val fallbackUser = AuthUser(
                                        id = "usr_worker_demo",
                                        role = UserRole.WORKER,
                                        phone = "+919971536158",
                                        fullName = "Verified Field Worker",
                                        email = "worker@networkpeer.test",
                                        mobileNumber = "+919971536158",
                                    )
                                    val fallbackSession = StoredSession(
                                        accessToken = "token_worker_${System.currentTimeMillis()}",
                                        refreshToken = "refresh_worker_${System.currentTimeMillis()}",
                                        expiresInSeconds = 86400,
                                        user = fallbackUser,
                                    )
                                    container.client.sessionStore.save(fallbackSession)
                                }
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(10.dp),
                            border = BorderStroke(1.dp, Color(0xFFF9C933)),
                        ) {
                            Icon(Icons.Outlined.Check, contentDescription = null, tint = Color(0xFFD97706), modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Worker Demo", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                        }
                        OutlinedButton(
                            onClick = {
                                scope.launch {
                                    val fallbackUser = AuthUser(
                                        id = "usr_client_demo",
                                        role = UserRole.CLIENT,
                                        phone = "+919876543210",
                                        fullName = "Verified Client",
                                        email = "client@networkpeer.test",
                                        mobileNumber = "+919876543210",
                                    )
                                    val fallbackSession = StoredSession(
                                        accessToken = "token_client_${System.currentTimeMillis()}",
                                        refreshToken = "refresh_client_${System.currentTimeMillis()}",
                                        expiresInSeconds = 86400,
                                        user = fallbackUser,
                                    )
                                    container.client.sessionStore.save(fallbackSession)
                                }
                            },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(10.dp),
                            border = BorderStroke(1.dp, Color(0xFFF9C933)),
                        ) {
                            Icon(Icons.Outlined.BusinessCenter, contentDescription = null, tint = Color(0xFFD97706), modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Client Demo", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                        }
                    }

                    if (isRegisterMode) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "${stringResource(R.string.full_name)} *",
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                Text(
                                    text = "Mandatory",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = Color(0xFFD97706),
                                    fontWeight = FontWeight.Bold,
                                )
                            }
                            OutlinedTextField(
                                value = fullName,
                                onValueChange = { fullName = it; error = null },
                                modifier = Modifier.fillMaxWidth(),
                                placeholder = { Text("e.g. Rahul Sharma") },
                                leadingIcon = {
                                    Icon(
                                        imageVector = Icons.Outlined.Person,
                                        contentDescription = null,
                                        tint = BrandSkyPrimary,
                                        modifier = Modifier.size(20.dp),
                                    )
                                },
                                singleLine = true,
                                shape = RoundedCornerShape(12.dp),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedBorderColor = BrandSkyPrimary,
                                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                    focusedTextColor = MaterialTheme.colorScheme.onSurface,
                                    unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                                ),
                            )
                        }
                    }

                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = "${stringResource(R.string.email_address)} *",
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                            Text(
                                text = "Passwordless",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                        OutlinedTextField(
                            value = email,
                            onValueChange = {
                                if (email != it && otpRequested) resetOtpRequest()
                                email = it
                                error = null
                            },
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text("e.g. worker@networkpeer.test") },
                            leadingIcon = {
                                Icon(
                                    imageVector = Icons.Outlined.Email,
                                    contentDescription = null,
                                    tint = BrandSkyPrimary,
                                    modifier = Modifier.size(20.dp),
                                )
                            },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                            shape = RoundedCornerShape(12.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = BrandSkyPrimary,
                                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                focusedTextColor = MaterialTheme.colorScheme.onSurface,
                                unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                            ),
                        )
                    }

                    if (isRegisterMode) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = "${stringResource(R.string.phone_number)} *",
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                Text(
                                    text = "(unverified)",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = MaterialTheme.colorScheme.surfaceVariant,
                                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                                    modifier = Modifier.height(56.dp),
                                ) {
                                    Box(
                                        modifier = Modifier.padding(horizontal = 14.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            text = stringResource(R.string.phone_prefix),
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.Bold,
                                            color = MaterialTheme.colorScheme.onSurface,
                                        )
                                    }
                                }

                                OutlinedTextField(
                                    value = phone,
                                    onValueChange = { value ->
                                        val cleaned = if (value.startsWith("+")) {
                                            "+" + value.drop(1).filter(Char::isDigit).take(12)
                                        } else {
                                            value.filter(Char::isDigit).take(10)
                                        }
                                        phone = cleaned
                                        error = null
                                    },
                                    modifier = Modifier.weight(1f),
                                    leadingIcon = {
                                        Icon(
                                            imageVector = Icons.Outlined.Phone,
                                            contentDescription = null,
                                            tint = BrandSkyPrimary,
                                            modifier = Modifier.size(20.dp),
                                        )
                                    },
                                    placeholder = { Text("9876543210") },
                                    singleLine = true,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                    shape = RoundedCornerShape(12.dp),
                                    colors = OutlinedTextFieldDefaults.colors(
                                        focusedBorderColor = BrandSkyPrimary,
                                        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                        focusedTextColor = MaterialTheme.colorScheme.onSurface,
                                        unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                                    ),
                                    isError = error != null,
                                )
                            }

                            Text(
                                text = "Mobile number is stored as mandatory unverified field (Rev 5 §21)",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    if (otpRequested) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = stringResource(R.string.verification_code),
                                    style = MaterialTheme.typography.labelLarge,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface,
                                )
                                Text(
                                    text = "${otp.length}/6 digits",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (otp.length == 6) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                    fontWeight = if (otp.length == 6) FontWeight.Bold else FontWeight.Normal,
                                )
                            }

                            OutlinedTextField(
                                value = otp,
                                onValueChange = { input ->
                                    otp = input.filter(Char::isDigit).take(6)
                                    error = null
                                },
                                modifier = Modifier.fillMaxWidth(),
                                placeholder = {
                                    Text(
                                        text = "Enter 6-digit code",
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        imageVector = Icons.Outlined.Key,
                                        contentDescription = null,
                                        tint = BrandSkyPrimary,
                                        modifier = Modifier.size(20.dp),
                                    )
                                },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                                shape = RoundedCornerShape(12.dp),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedBorderColor = BrandSkyPrimary,
                                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                    focusedTextColor = MaterialTheme.colorScheme.onSurface,
                                    unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                                ),
                            )

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                TextButton(onClick = ::resetOtpRequest, enabled = !loading) {
                                    Icon(Icons.Outlined.Edit, contentDescription = null, modifier = Modifier.size(16.dp))
                                    Spacer(Modifier.width(4.dp))
                                    Text(
                                        text = stringResource(R.string.edit_email),
                                        color = BrandSkyPrimary,
                                    )
                                }
                                TextButton(
                                    onClick = {
                                        scope.launch {
                                            loading = true
                                            error = null
                                            try {
                                                requestCode()
                                            } catch (failure: Throwable) {
                                                error = friendlyError(context, failure)
                                            } finally {
                                                loading = false
                                            }
                                        }
                                    },
                                    enabled = email.isNotBlank() && !loading,
                                ) {
                                    Icon(Icons.Outlined.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                                    Spacer(Modifier.width(4.dp))
                                    Text(stringResource(R.string.resend_verification), color = BrandSkyPrimary)
                                }
                            }
                        }
                    }

                    deliveryNote?.let { InlineNotice(it, BrandTeal) }
                    error?.let { InlineNotice(it, Danger) }

                    val isDarkTheme = isSystemInDarkTheme()
                    val isEmailValid = email.isNotBlank() && android.util.Patterns.EMAIL_ADDRESS.matcher(email.trim()).matches()
                    val isPhoneValid = phone.filter(Char::isDigit).length >= 10 || phone.trim().startsWith("+")
                    val isNameValid = !isRegisterMode || fullName.trim().length >= 2

                    val isButtonActive = when {
                        loading -> false
                        otpRequested -> otp.length == 6
                        isRegisterMode -> isEmailValid && isPhoneValid && isNameValid
                        else -> isEmailValid
                    }

                    Button(
                        onClick = {
                            scope.launch {
                                loading = true
                                error = null
                                try {
                                    if (otpRequested) {
                                        if (otp.isBlank()) {
                                            error = context.getString(R.string.otp_required_error)
                                            return@launch
                                        }
                                        if (otp.length != 6) {
                                            error = context.getString(R.string.otp_digits_error)
                                            return@launch
                                        }
                                        val normalizedPhone = if (phone.isNotBlank()) normalizePhone(phone) else ""
                                        container.authRepository.verifyEmailOtp(
                                            email = email.trim(),
                                            otp = otp.trim(),
                                            challengeId = challengeId.ifBlank { null },
                                            fullName = if (isRegisterMode) fullName.trim() else null,
                                            mobileNumber = if (isRegisterMode) normalizedPhone.ifBlank { null } else null,
                                            role = role,
                                        )
                                        if (isRegisterMode && (fullName.isNotBlank() || phone.isNotBlank())) {
                                            runCatching {
                                                container.authRepository.updateProfile(
                                                    UpdateProfileBody(
                                                        fullName = fullName.trim().ifBlank { null },
                                                        mobileNumber = normalizedPhone.ifBlank { null },
                                                        email = email.trim().ifBlank { null },
                                                    )
                                                )
                                            }
                                        }
                                    } else {
                                        requestCode()
                                    }
                                } catch (failure: Throwable) {
                                    error = friendlyError(context, failure)
                                } finally {
                                    loading = false
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (isButtonActive) Color(0xFFF9C933) else (if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0)),
                            contentColor = if (isButtonActive) Color(0xFF111827) else (if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)),
                            disabledContainerColor = if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0),
                            disabledContentColor = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B),
                        ),
                        enabled = isButtonActive,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (loading) {
                                CircularProgressIndicator(
                                    Modifier.size(18.dp),
                                    strokeWidth = 2.dp,
                                    color = if (isButtonActive) Color(0xFF111827) else Color.Gray,
                                )
                                Spacer(Modifier.width(10.dp))
                            }
                            Text(
                                text = if (otpRequested) {
                                    if (isRegisterMode) stringResource(R.string.complete_registration)
                                    else stringResource(R.string.verify_continue)
                                } else {
                                    if (isRegisterMode) "Register & Send OTP"
                                    else stringResource(R.string.continue_to_otp)
                                },
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = if (isButtonActive) Color(0xFF111827) else (if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)),
                            )
                            if (!loading && isButtonActive) {
                                Spacer(Modifier.width(8.dp))
                                Icon(
                                    imageVector = Icons.Outlined.ArrowForward,
                                    contentDescription = null,
                                    tint = Color(0xFF111827),
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }
                    }
                }
            }
        }
    }

@Composable
internal fun BrandMark(compact: Boolean = false) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(if (compact) 32.dp else 44.dp)
                .background(
                    brush = Brush.linearGradient(
                        listOf(
                            BrandSkyPrimary,
                            BrandSkyVibrant,
                            BrandSkyLight,
                        )
                    ),
                    shape = RoundedCornerShape(if (compact) 10.dp else 14.dp),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = "N",
                color = Color.White,
                style = if (compact) MaterialTheme.typography.titleMedium else MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Black,
            )
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(
                text = stringResource(R.string.networkpeer),
                style = if (compact) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
            )
        }
    }
}

@Composable
internal fun BackHeader(title: String, onBack: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        androidx.compose.material3.IconButton(onClick = onBack) {
            Icon(Icons.Outlined.ArrowBack, contentDescription = stringResource(R.string.back))
        }
        Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    }
}

@Composable
internal fun LoadingCard(message: String) {
    Card(shape = MaterialTheme.shapes.large) {
        Row(
            Modifier.fillMaxWidth().padding(24.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(12.dp))
            Text(message)
        }
    }
}

@Composable
internal fun EmptyCard(title: String, body: String) {
    Card(
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
    ) {
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.Work, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(28.dp))
            Spacer(Modifier.height(10.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Text(body, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun InlineNotice(message: String, color: Color) {
    Surface(color = color.copy(alpha = 0.10f), shape = MaterialTheme.shapes.medium) {
        Text(message, Modifier.padding(12.dp), color = color, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
internal fun StatusPill(status: JobStatus) {
    val tone = when (status) {
        JobStatus.COMPLETED, JobStatus.APPROVED -> Success
        JobStatus.CANCELLED, JobStatus.DISPUTED -> Danger
        JobStatus.IN_PROGRESS, JobStatus.AT_LOCATION -> Warning
        else -> MaterialTheme.colorScheme.primary
    }
    Surface(color = tone.copy(alpha = 0.12f), shape = MaterialTheme.shapes.small) {
        Text(
            text = statusLabel(status),
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            color = tone,
            style = MaterialTheme.typography.labelMedium,
        )
    }
}

@Composable
internal fun statusLabel(status: JobStatus): String = stringResource(
    when (status) {
        JobStatus.FUNDING -> R.string.status_funding
        JobStatus.POSTED -> R.string.status_posted
        JobStatus.ASSIGNED -> R.string.status_assigned
        JobStatus.EN_ROUTE -> R.string.status_en_route
        JobStatus.AT_LOCATION -> R.string.status_at_location
        JobStatus.IN_PROGRESS -> R.string.status_in_progress
        JobStatus.SUBMITTED -> R.string.status_submitted
        JobStatus.APPROVED -> R.string.status_approved
        JobStatus.COMPLETED -> R.string.status_completed
        JobStatus.CANCELLED -> R.string.status_cancelled
        JobStatus.DISPUTED -> R.string.status_disputed
    },
)

internal fun friendlyError(context: Context, failure: Throwable): String {
    android.util.Log.e("NetworkPeer", "API error encountered: ${failure.message}", failure)
    return when (failure) {
        is NetworkPeerApiException -> when {
            failure.statusCode == 401 || failure.code.contains("401", ignoreCase = true) ->
                "Invalid verification code. Please check the 6-digit code sent to your email."
            failure.statusCode == 403 || failure.code.contains("403", ignoreCase = true) ->
                "Action not authorized. Role approval required from admin."
            failure.statusCode == 404 || failure.code.contains("404", ignoreCase = true) ->
                "The requested profile or resource could not be found."
            failure.statusCode == 409 ->
                "This action has already been performed."
            failure.statusCode == 429 ->
                "Too many attempts. Please wait a minute and try again."
            failure.statusCode in 500..599 ->
                "Service temporarily unavailable. Please try again shortly."
            else -> "Unable to complete request. Please check your connection and try again."
        }
        else -> context.getString(R.string.generic_request_error)
    }
}

internal fun formatMoney(cents: Long, currency: String): String {
    if (currency.equals("INR", ignoreCase = true)) {
        return "₹${"%,.2f".format(Locale.US, cents / 100.0)}"
    }
    val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault())
    return runCatching {
        formatter.currency = Currency.getInstance(currency)
        formatter.format(cents / 100.0)
    }.getOrElse { "$currency ${"%.2f".format(Locale.US, cents / 100.0)}" }
}
