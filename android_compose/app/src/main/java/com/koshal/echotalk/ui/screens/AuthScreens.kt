package com.koshal.echotalk.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Security
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.koshal.echotalk.ui.theme.*
import com.koshal.echotalk.viewmodel.EchoViewModel

@Composable
fun EntryScreen(
    viewModel: EchoViewModel,
    onGuestProceed: () -> Unit,
    onPhoneAuth: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BgDark)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Spacer(modifier = Modifier.height(20.dp))

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                modifier = Modifier
                    .size(90.dp)
                    .clip(CircleShape)
                    .background(Brush.linearGradient(listOf(PrimaryPurple, AccentCyan))),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Mic, contentDescription = null, tint = TextPrimary, modifier = Modifier.size(46.dp))
            }
            Spacer(modifier = Modifier.height(24.dp))
            Text("ECHO", fontSize = 32.sp, fontWeight = FontWeight.Black, color = TextPrimary, letterSpacing = 3.sp)
            Text("Talk to Strangers", fontSize = 14.sp, color = TextSecondary)
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                "Live spontaneous audio & video conversations with people worldwide.",
                textAlign = TextAlign.Center,
                fontSize = 13.sp,
                color = TextSecondary,
                lineHeight = 18.sp
            )
        }

        Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // Guest Notice
            Card(
                colors = CardDefaults.cardColors(containerColor = SurfaceDark),
                shape = RoundedCornerShape(14.dp)
            ) {
                Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("⏱️", fontSize = 20.sp)
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        "Guests get 60 minutes total use & 30 minutes free video calling without registration.",
                        fontSize = 12.sp,
                        color = TextSecondary
                    )
                }
            }

            Button(
                onClick = {
                    viewModel.loginAsGuest()
                    onGuestProceed()
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = PrimaryPurple)
            ) {
                Text("Continue as Guest (60 Mins)", fontWeight = FontWeight.Bold)
            }

            // Phone OTP login is not available yet (no SMS provider connected).
            OutlinedButton(
                onClick = onPhoneAuth,
                enabled = false,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = TextPrimary)
            ) {
                Icon(Icons.Default.Phone, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Phone Number Login: Coming soon")
            }
        }

        Text(
            "By continuing, you accept Echo Terms & 18+ UGC Community Guidelines.",
            fontSize = 11.sp,
            color = TextSecondary.copy(alpha = 0.6f),
            textAlign = TextAlign.Center
        )
    }
}

@Composable
fun PhoneOtpScreen(
    onVerified: () -> Unit
) {
    var phone by remember { mutableStateOf("") }
    var otpCode by remember { mutableStateOf("") }
    var step by remember { mutableStateOf(1) } // 1 = enter phone, 2 = enter otp
    var attemptsLeft by remember { mutableStateOf(5) }
    var timerSeconds by remember { mutableStateOf(300) } // 5 mins
    var resendCooldown by remember { mutableStateOf(0) }
    var statusMessage by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BgDark)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(Icons.Default.Security, contentDescription = null, tint = PrimaryPurple, modifier = Modifier.size(48.dp))
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            if (step == 1) "Enter Phone Number" else "Enter 6-Digit OTP",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = TextPrimary
        )
        Text(
            if (step == 1) "We'll send a 6-digit code valid for 5 minutes." else "Code sent to $phone. Max 5 attempts.",
            fontSize = 12.sp,
            color = TextSecondary,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(24.dp))

        if (step == 1) {
            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("10-Digit Mobile Number") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp)
            )
            Spacer(modifier = Modifier.height(16.dp))
            Button(
                onClick = {
                    if (phone.length >= 10) {
                        step = 2
                        statusMessage = "OTP sent! Check phone or local server console."
                    }
                },
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = PrimaryPurple)
            ) {
                Text("Send Code", fontWeight = FontWeight.Bold)
            }
        } else {
            OutlinedTextField(
                value = otpCode,
                onValueChange = { if (it.length <= 6) otpCode = it },
                label = { Text("6-Digit Code") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text("Attempts remaining: $attemptsLeft", fontSize = 11.sp, color = if (attemptsLeft <= 2) DangerRed else TextSecondary)
            Spacer(modifier = Modifier.height(16.dp))
            Button(
                onClick = {
                    if (otpCode.length == 6) {
                        onVerified()
                    } else {
                        attemptsLeft--
                        statusMessage = "Incorrect code. $attemptsLeft tries left."
                    }
                },
                modifier = Modifier.fillMaxWidth().height(50.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = SuccessGreen)
            ) {
                Text("Verify & Continue", fontWeight = FontWeight.Bold)
            }
        }

        if (statusMessage.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))
            Text(statusMessage, fontSize = 12.sp, color = PrimaryPurple)
        }
    }
}
