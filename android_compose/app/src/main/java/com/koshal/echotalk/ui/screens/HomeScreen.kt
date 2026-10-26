package com.koshal.echotalk.ui.screens

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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.koshal.echotalk.ui.theme.*
import com.koshal.echotalk.viewmodel.EchoViewModel

@Composable
fun HomeScreen(
    viewModel: EchoViewModel,
    onStartCall: (String) -> Unit,
    onOpenChats: () -> Unit,
    onOpenCoins: () -> Unit,
    onOpenProfile: () -> Unit,
    onOpenSafety: () -> Unit
) {
    val user by viewModel.currentUser.collectAsState()
    val guestTotalSec by viewModel.guestTotalSeconds.collectAsState()
    val settings by viewModel.systemSettings.collectAsState()
    val broadcast by viewModel.broadcastAlert.collectAsState()
    val giftNotice by viewModel.giftCoinsAlert.collectAsState()

    var selectedTab by remember { mutableStateOf(0) }

    fun formatTimer(seconds: Int): String {
        val m = seconds / 60
        val s = seconds % 60
        return "%02d:%02d".format(m, s)
    }

    Scaffold(
        containerColor = BgDark,
        topBar = {
            Column {
                // Admin Instant Broadcast Bar
                broadcast?.let { msg ->
                    Surface(
                        color = PrimaryPurple,
                        modifier = Modifier.fillMaxWidth().clickable { viewModel.dismissBroadcastAlert() }
                    ) {
                        Text(
                            text = "📢 ALERT: $msg",
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(vertical = 6.dp, horizontal = 12.dp)
                        )
                    }
                }

                // Top Bar (Matching Image 2 Screen 4)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Menu, contentDescription = "Menu", tint = TextSecondary, modifier = Modifier.size(24.dp))
                        Spacer(modifier = Modifier.width(10.dp))
                        Text("Echo", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                    }

                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Coin Pill Badge
                        Surface(
                            color = SurfaceElevated,
                            shape = RoundedCornerShape(16.dp),
                            border = androidx.compose.foundation.BorderStroke(1.dp, AmberGold.copy(alpha = 0.4f)),
                            modifier = Modifier.clickable { onOpenCoins() }
                        ) {
                            Row(modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text("🪙 ", fontSize = 11.sp)
                                Text("${user?.coins ?: 50}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AmberGold)
                            }
                        }

                        // User Avatar
                        Box(
                            modifier = Modifier
                                .size(34.dp)
                                .clip(CircleShape)
                                .background(SurfaceElevated)
                                .clickable { onOpenProfile() },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Person, contentDescription = null, tint = AccentCyan, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }
        },
        bottomBar = {
            // Bottom Navigation (Home, Chats, Coins, Profile - Matching Images 2 & 3)
            NavigationBar(containerColor = SurfaceDark) {
                NavigationBarItem(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    icon = { Icon(Icons.Default.Home, contentDescription = null) },
                    label = { Text("Home") }
                )
                NavigationBarItem(
                    selected = selectedTab == 1,
                    onClick = { onOpenChats() },
                    icon = { Icon(Icons.Default.ChatBubbleOutline, contentDescription = null) },
                    label = { Text("Chats") }
                )
                NavigationBarItem(
                    selected = selectedTab == 2,
                    onClick = { onOpenCoins() },
                    icon = { Icon(Icons.Default.MonetizationOn, contentDescription = null) },
                    label = { Text("Coins") }
                )
                NavigationBarItem(
                    selected = selectedTab == 3,
                    onClick = { onOpenProfile() },
                    icon = { Icon(Icons.Default.PersonOutline, contentDescription = null) },
                    label = { Text("Profile") }
                )
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Gift Pop-up Banner if admin sends coins
            giftNotice?.let { msg ->
                Card(
                    colors = CardDefaults.cardColors(containerColor = AmberGold.copy(alpha = 0.15f)),
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier.fillMaxWidth().clickable { viewModel.dismissGiftCoinsAlert() }
                ) {
                    Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("🎁 ", fontSize = 18.sp)
                        Text(msg, fontSize = 12.sp, color = AmberGold, fontWeight = FontWeight.Bold)
                    }
                }
            }

            // Announcement Card (Matching Image 2 Screen 4)
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(containerColor = SurfaceElevated),
                border = androidx.compose.foundation.BorderStroke(1.dp, PrimaryPurple.copy(alpha = 0.3f))
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column {
                        Text("Welcome to Echo! 🎉", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                        Spacer(modifier = Modifier.height(2.dp))
                        Text("Get 50 free coins on your first sign up!", fontSize = 11.sp, color = PrimaryPurple)
                    }
                    Text("✨", fontSize = 18.sp)
                }
            }

            // Big Card 1: Random Call (Pink/Purple Gradient - Matching Image 2)
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(115.dp)
                    .clickable { onStartCall("audio") },
                shape = RoundedCornerShape(24.dp),
                colors = CardDefaults.cardColors(containerColor = Color.Transparent)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Brush.horizontalGradient(listOf(Color(0xFFE056FD), Color(0xFF686DE0))))
                        .padding(horizontal = 20.dp),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(50.dp)
                                .clip(RoundedCornerShape(16.dp))
                                .background(Color.White.copy(alpha = 0.25f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Phone, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
                        }
                        Spacer(modifier = Modifier.width(16.dp))
                        Column {
                            Text("Random Call", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
                            Text("Find someone now", fontSize = 12.sp, color = Color.White.copy(alpha = 0.85f))
                        }
                    }
                }
            }

            // Big Card 2: Video Call (Cyan/Blue Gradient - Matching Image 2)
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(115.dp)
                    .clickable { onStartCall("video") },
                shape = RoundedCornerShape(24.dp),
                colors = CardDefaults.cardColors(containerColor = Color.Transparent)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Brush.horizontalGradient(listOf(Color(0xFF22A6B3), Color(0xFF30336B))))
                        .padding(horizontal = 20.dp),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(50.dp)
                                .clip(RoundedCornerShape(16.dp))
                                .background(Color.White.copy(alpha = 0.25f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Videocam, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
                        }
                        Spacer(modifier = Modifier.width(16.dp))
                        Column {
                            Text("Video Call", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
                            Text("Start a video chat", fontSize = 12.sp, color = Color.White.copy(alpha = 0.85f))
                        }
                    }
                }
            }

            // Bottom Two Info Chips (Free Coins & Username - Matching Image 2)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Card(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("Free Coins", fontSize = 10.sp, color = TextSecondary)
                        Spacer(modifier = Modifier.height(2.dp))
                        Text("🪙 50", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = AmberGold)
                    }
                }

                Card(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("Your Username", fontSize = 10.sp, color = TextSecondary)
                        Spacer(modifier = Modifier.height(2.dp))
                        Text("@${user?.username ?: "Alex_23"}", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = AccentCyan)
                    }
                }
            }

            // Guest Timer Badge (if in guest mode)
            if (user?.isGuest == true) {
                Surface(
                    color = SurfaceDark,
                    shape = RoundedCornerShape(12.dp),
                    border = androidx.compose.foundation.BorderStroke(1.dp, PrimaryPurple.copy(alpha = 0.3f)),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("⏱️ Guest session: ${formatTimer(guestTotalSec)} remaining", fontSize = 11.sp, color = TextSecondary)
                        Text("Upgrade", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = PrimaryPurple)
                    }
                }
            }
        }
    }
}
