package com.koshal.echotalk.ui.screens

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.koshal.echotalk.data.model.VirtualGift
import com.koshal.echotalk.ui.theme.*
import com.koshal.echotalk.viewmodel.EchoViewModel

@Composable
fun CallScreen(
    viewModel: EchoViewModel,
    onCallFinished: () -> Unit
) {
    val call by viewModel.activeCall.collectAsState()
    var isMuted by remember { mutableStateOf(false) }
    var isCameraOff by remember { mutableStateOf(false) }
    var callSeconds by remember { mutableStateOf(0) }
    var showGiftSentMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(1000)
            callSeconds++
        }
    }

    if (call == null) {
        onCallFinished()
        return
    }

    fun formatTimer(sec: Int): String {
        val m = sec / 60
        val s = sec % 60
        return "%02d:%02d".format(m, s)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BgDark)
    ) {
        // Main Screen Content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            // Header with Back and Local PIP Camera Window
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                IconButton(onClick = { viewModel.endCall() }) {
                    Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = TextPrimary)
                }

                // Local PIP Box
                Box(
                    modifier = Modifier
                        .size(width = 75.dp, height = 100.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(SurfaceElevated),
                    contentAlignment = Alignment.BottomEnd
                ) {
                    Icon(
                        Icons.Default.Person,
                        contentDescription = null,
                        tint = AccentCyan,
                        modifier = Modifier.align(Alignment.Center).size(40.dp)
                    )
                    Surface(
                        color = Color.Black.copy(alpha = 0.6f),
                        shape = RoundedCornerShape(4.dp),
                        modifier = Modifier.padding(4.dp)
                    ) {
                        Text("You", color = Color.White, fontSize = 9.sp, modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp))
                    }
                }
            }

            // Remote Caller View (Matching Image 2 Screen 6)
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    modifier = Modifier
                        .size(130.dp)
                        .clip(CircleShape)
                        .background(SurfaceElevated),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.Person, contentDescription = null, tint = AccentCyan, modifier = Modifier.size(70.dp))
                }
                Spacer(modifier = Modifier.height(14.dp))
                Text(call?.strangerName ?: "Jenny_19", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(SuccessGreen))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Online", fontSize = 12.sp, color = SuccessGreen, fontWeight = FontWeight.Bold)
                }

                Spacer(modifier = Modifier.height(4.dp))
                Text(formatTimer(callSeconds), fontSize = 14.sp, fontFeatureSettings = "tnum", color = AccentCyan, fontWeight = FontWeight.Bold)

                // Virtual Gifts Tray (Feature from prompt!)
                Spacer(modifier = Modifier.height(18.dp))
                Surface(
                    color = SurfaceElevated.copy(alpha = 0.8f),
                    shape = RoundedCornerShape(20.dp),
                    border = androidx.compose.foundation.BorderStroke(1.dp, PrimaryPurple.copy(alpha = 0.4f))
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        VirtualGift.GIFTS.take(4).forEach { gift ->
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                modifier = Modifier.clickable {
                                    showGiftSentMessage = "Sent ${gift.name} ${gift.icon}!"
                                }
                            ) {
                                Text(gift.icon, fontSize = 22.sp)
                                Text("${gift.coins} 🪙", fontSize = 9.sp, color = AmberGold, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }

                showGiftSentMessage?.let {
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(it, fontSize = 11.sp, color = AmberGold, fontWeight = FontWeight.Bold)
                }
            }

            // Call Controls: Mute, Red End Call, Camera Off (Matching Image 2 Screen 6)
            Row(
                modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Mute
                IconButton(
                    onClick = {
                        viewModel.webrtcEngine?.toggleMute()
                        isMuted = !isMuted
                    },
                    modifier = Modifier.size(54.dp).clip(CircleShape).background(if (isMuted) DangerRed else SurfaceElevated)
                ) {
                    Icon(if (isMuted) Icons.Default.MicOff else Icons.Default.Mic, contentDescription = "Mute", tint = Color.White)
                }

                // Big Red End Call Button
                IconButton(
                    onClick = { viewModel.endCall() },
                    modifier = Modifier.size(68.dp).clip(CircleShape).background(DangerRed)
                ) {
                    Icon(Icons.Default.CallEnd, contentDescription = "End Call", tint = Color.White, modifier = Modifier.size(32.dp))
                }

                // Camera Off
                IconButton(
                    onClick = {
                        viewModel.webrtcEngine?.toggleCamera()
                        isCameraOff = !isCameraOff
                    },
                    modifier = Modifier.size(54.dp).clip(CircleShape).background(if (isCameraOff) DangerRed else SurfaceElevated)
                ) {
                    Icon(if (isCameraOff) Icons.Default.VideocamOff else Icons.Default.Videocam, contentDescription = "Camera", tint = Color.White)
                }
            }
        }
    }
}
