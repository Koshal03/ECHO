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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.koshal.echotalk.ui.theme.*
import com.koshal.echotalk.viewmodel.EchoViewModel

// =================== 11. PROFILE SCREEN (Image 3) ===================
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    viewModel: EchoViewModel,
    onBack: () -> Unit,
    onOpenCoins: () -> Unit,
    onOpenChats: () -> Unit,
    onOpenSafety: () -> Unit,
    onLoggedOut: () -> Unit
) {
    val user by viewModel.currentUser.collectAsState()
    var showDeleteDialog by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = BgDark,
        topBar = {
            TopAppBar(
                title = { Text("Profile", color = TextPrimary) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = TextPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BgDark)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Profile Header
            Box(
                modifier = Modifier
                    .size(90.dp)
                    .clip(CircleShape)
                    .background(SurfaceElevated),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Person, contentDescription = null, tint = AccentCyan, modifier = Modifier.size(52.dp))
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(user?.displayName ?: "Alex_23", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                Text("@${user?.username ?: "Alex_23"}", fontSize = 12.sp, color = TextSecondary)
            }

            // Stats Row: 12 Calls | 8 Followers | 3 Following (Matching Image 3 Screen 11)
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("12", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                    Text("Calls", fontSize = 11.sp, color = TextSecondary)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("8", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                    Text("Followers", fontSize = 11.sp, color = TextSecondary)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("3", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                    Text("Following", fontSize = 11.sp, color = TextSecondary)
                }
            }

            // Profile Menu List (Matching Image 3 Screen 11)
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
            ) {
                Column(modifier = Modifier.padding(vertical = 4.dp)) {
                    ProfileMenuItem(icon = Icons.Default.Person, label = "Edit Profile") {}
                    Divider(color = Color.White.copy(alpha = 0.05f))
                    ProfileMenuItem(
                        icon = Icons.Default.MonetizationOn,
                        label = "Coins & Wallet",
                        trailingBadge = "${user?.coins ?: 50} 🪙",
                        onClick = onOpenCoins
                    )
                    Divider(color = Color.White.copy(alpha = 0.05f))
                    ProfileMenuItem(icon = Icons.Default.ChatBubbleOutline, label = "Chat History", onClick = onOpenChats)
                    Divider(color = Color.White.copy(alpha = 0.05f))
                    ProfileMenuItem(icon = Icons.Default.Block, label = "Blocked Users", onClick = onOpenSafety)
                    Divider(color = Color.White.copy(alpha = 0.05f))
                    ProfileMenuItem(icon = Icons.Default.Flag, label = "Report History", onClick = onOpenSafety)
                    Divider(color = Color.White.copy(alpha = 0.05f))
                    ProfileMenuItem(icon = Icons.Default.Settings, label = "Settings") {}
                }
            }

            // Delete Account Button (Google Play Mandatory)
            Card(
                modifier = Modifier.fillMaxWidth().clickable { showDeleteDialog = true },
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = DangerRed.copy(alpha = 0.1f))
            ) {
                Row(
                    modifier = Modifier.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.DeleteOutline, contentDescription = null, tint = DangerRed)
                    Spacer(modifier = Modifier.width(12.dp))
                    Text("Delete Account & Data", fontSize = 13.sp, color = DangerRed, fontWeight = FontWeight.Bold)
                }
            }
        }

        if (showDeleteDialog) {
            AlertDialog(
                onDismissRequest = { showDeleteDialog = false },
                containerColor = SurfaceDark,
                title = { Text("Delete Account?", color = DangerRed) },
                text = {
                    Text(
                        "This will immediately purge your account, coin balance, and history from Echo servers in accordance with Google Play privacy rules.",
                        fontSize = 12.sp,
                        color = TextSecondary
                    )
                },
                confirmButton = {
                    Button(
                        onClick = {
                            viewModel.deleteMyAccount {
                                showDeleteDialog = false
                                onLoggedOut()
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = DangerRed)
                    ) {
                        Text("Delete Account")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showDeleteDialog = false }) {
                        Text("Cancel", color = TextSecondary)
                    }
                }
            )
        }
    }
}

@Composable
fun ProfileMenuItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    trailingBadge: String? = null,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, tint = AccentCyan, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(14.dp))
            Text(label, fontSize = 13.sp, color = TextPrimary)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            trailingBadge?.let {
                Text(it, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = AmberGold)
                Spacer(modifier = Modifier.width(8.dp))
            }
            Icon(Icons.Default.ChevronRight, contentDescription = null, tint = TextSecondary, modifier = Modifier.size(16.dp))
        }
    }
}

// =================== 14. CHATS / HISTORY SCREEN (Image 3) ===================
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatsScreen(onBack: () -> Unit) {
    var selectedTab by remember { mutableStateOf(0) }
    val sampleChats = listOf(
        Pair("Jenny_19", "Hey, nice to meet you! • 2m ago"),
        Pair("MysteryGirl", "That's fun! :) • 15m ago"),
        Pair("User_555", "See you soon! • 35m ago"),
        Pair("Dreamer", "Nice talking to you! • 1h ago"),
        Pair("CoolVoice_412", "Good vibes 😎 • 2h ago")
    )

    Scaffold(
        containerColor = BgDark,
        topBar = {
            TopAppBar(
                title = { Text("Chats", color = TextPrimary) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = TextPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BgDark)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Tab Toggle: Recent / Favorites (Matching Image 3 Screen 14)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(SurfaceElevated)
                    .padding(3.dp)
            ) {
                Surface(
                    color = if (selectedTab == 0) PrimaryPurple else Color.Transparent,
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.weight(1f).clickable { selectedTab = 0 }
                ) {
                    Text("Recent", textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(vertical = 8.dp), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White)
                }
                Surface(
                    color = if (selectedTab == 1) PrimaryPurple else Color.Transparent,
                    shape = RoundedCornerShape(10.dp),
                    modifier = Modifier.weight(1f).clickable { selectedTab = 1 }
                ) {
                    Text("Favorites", textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.padding(vertical = 8.dp), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = TextSecondary)
                }
            }

            // Chat List
            sampleChats.forEach { chat ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp),
                    colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
                ) {
                    Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier.size(40.dp).clip(CircleShape).background(PrimaryPurple.copy(alpha = 0.2f)),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(Icons.Default.Person, contentDescription = null, tint = AccentCyan, modifier = Modifier.size(24.dp))
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(chat.first, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                            Text(chat.second, fontSize = 11.sp, color = TextSecondary)
                        }
                    }
                }
            }
        }
    }
}

// =================== 16. SAFETY & SUPPORT SCREEN (Image 3) ===================
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SafetyScreen(onBack: () -> Unit) {
    Scaffold(
        containerColor = BgDark,
        topBar = {
            TopAppBar(
                title = { Text("Safety & Support", color = TextPrimary) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = TextPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BgDark)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SafetyItem(icon = Icons.Default.Block, title = "Block User", desc = "Prevent them from contacting you.", color = DangerRed)
            SafetyItem(icon = Icons.Default.Report, title = "Report User", desc = "Help keep Echo safe.", color = DangerRed)
            SafetyItem(icon = Icons.Default.MenuBook, title = "Community Guidelines", desc = "Be respectful. Be kind.", color = AccentCyan)
            SafetyItem(icon = Icons.Default.Help, title = "Help Center", desc = "Get support and FAQs.", color = PrimaryPurple)
            SafetyItem(icon = Icons.Default.Description, title = "Terms of Service", desc = "Read our terms and policies.", color = TextSecondary)
        }
    }
}

@Composable
fun SafetyItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    desc: String,
    color: Color
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
    ) {
        Row(modifier = Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)).background(color.copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(22.dp))
            }
            Spacer(modifier = Modifier.width(14.dp))
            Column {
                Text(title, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                Text(desc, fontSize = 11.sp, color = TextSecondary)
            }
        }
    }
}
