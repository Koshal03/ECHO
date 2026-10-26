package com.koshal.echotalk.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.koshal.echotalk.data.model.CoinPack
import com.koshal.echotalk.data.model.VirtualGift
import com.koshal.echotalk.ui.theme.*
import com.koshal.echotalk.viewmodel.EchoViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CoinStoreScreen(
    viewModel: EchoViewModel,
    onBack: () -> Unit
) {
    val user by viewModel.currentUser.collectAsState()

    Scaffold(
        containerColor = BgDark,
        topBar = {
            TopAppBar(
                title = { Text("Coins", color = TextPrimary) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = TextPrimary)
                    }
                },
                actions = {
                    Surface(
                        color = SurfaceElevated,
                        shape = RoundedCornerShape(16.dp),
                        border = androidx.compose.foundation.BorderStroke(1.dp, AmberGold.copy(alpha = 0.4f)),
                        modifier = Modifier.padding(end = 16.dp)
                    ) {
                        Row(modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("🪙 ", fontSize = 11.sp)
                            Text("${user?.coins ?: 50}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AmberGold)
                        }
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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("Get More Coins", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = TextPrimary)

            // 4 Packs Grid (Matching Image 3 Screen 12)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // Pack 1: 50 Coins ₹49
                Card(
                    modifier = Modifier.weight(1f).clickable { viewModel.addCoins(50) },
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("🪙", fontSize = 28.sp)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("50 Coins", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                        Text("₹49", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = PrimaryPurple)
                    }
                }

                // Pack 2: 200 Coins ₹149 (Popular)
                Card(
                    modifier = Modifier.weight(1f).clickable { viewModel.addCoins(200) },
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = SurfaceElevated),
                    border = androidx.compose.foundation.BorderStroke(2.dp, AccentCyan)
                ) {
                    Box(modifier = Modifier.fillMaxWidth()) {
                        Surface(
                            color = AccentCyan,
                            shape = RoundedCornerShape(topStart = 0.dp, bottomStart = 8.dp, bottomEnd = 0.dp, topEnd = 20.dp),
                            modifier = Modifier.align(Alignment.TopEnd)
                        ) {
                            Text("Popular", fontSize = 9.sp, fontWeight = FontWeight.Black, color = Color.Black, modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp))
                        }
                        Column(
                            modifier = Modifier.padding(16.dp).fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text("🪙", fontSize = 28.sp)
                            Spacer(modifier = Modifier.height(4.dp))
                            Text("200 Coins", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                            Text("₹149", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AccentCyan)
                        }
                    }
                }
            }

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // Pack 3: 500 Coins ₹299
                Card(
                    modifier = Modifier.weight(1f).clickable { viewModel.addCoins(500) },
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("🪙", fontSize = 28.sp)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("500 Coins", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                        Text("₹299", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = PrimaryPurple)
                    }
                }

                // Pack 4: 1,200 Coins ₹499
                Card(
                    modifier = Modifier.weight(1f).clickable { viewModel.addCoins(1200) },
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("🪙", fontSize = 28.sp)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("1,200 Coins", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
                        Text("₹499", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = PrimaryPurple)
                    }
                }
            }

            // Watch Ads Button (Matching Image 3 Screen 12)
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.addCoins(10) },
                shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(containerColor = Color.Transparent)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Brush.horizontalGradient(listOf(Color(0xFF8E44AD), Color(0xFF6C5CE7))))
                        .padding(16.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(
                                modifier = Modifier
                                    .size(44.dp)
                                    .clip(CircleShape)
                                    .background(Color.White.copy(alpha = 0.2f)),
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(Icons.Default.PlayCircle, contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp))
                            }
                            Spacer(modifier = Modifier.width(14.dp))
                            Column {
                                Text("Watch Ads", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                Text("Get 10 Coins", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AccentCyan)
                                Text("(1/1 per hr)", fontSize = 10.sp, color = Color.White.copy(alpha = 0.7f))
                            }
                        }
                    }
                }
            }

            // Virtual Gifts & Premium Cosmetics
            Text("Virtual Gifts & Premium Perks", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = TextPrimary)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                VirtualGift.GIFTS.take(3).forEach { gift ->
                    Card(
                        modifier = Modifier.weight(1f),
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(containerColor = SurfaceElevated)
                    ) {
                        Column(
                            modifier = Modifier.padding(10.dp).fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(gift.icon, fontSize = 20.sp)
                            Text(gift.name, fontSize = 10.sp, color = TextPrimary, maxLines = 1)
                            Text("${gift.coins} 🪙", fontSize = 11.sp, color = AmberGold, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
