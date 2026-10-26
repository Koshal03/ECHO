package com.koshal.echotalk

import android.Manifest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.*
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.koshal.echotalk.ui.screens.*
import com.koshal.echotalk.ui.theme.EchoTheme
import com.koshal.echotalk.viewmodel.EchoViewModel
import com.google.android.gms.ads.MobileAds

class MainActivity : ComponentActivity() {

    private val viewModel: EchoViewModel by viewModels()

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val micGranted = permissions[Manifest.permission.RECORD_AUDIO] ?: false
        val camGranted = permissions[Manifest.permission.CAMERA] ?: false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize Google Mobile Ads SDK
        MobileAds.initialize(this) {}

        // Request audio & camera permissions for WebRTC calls
        requestPermissionLauncher.launch(
            arrayOf(
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.CAMERA
            )
        )

        setContent {
            EchoTheme {
                val navController = rememberNavController()
                val activeCall by viewModel.activeCall.collectAsState()

                // Auto-navigate to call screen when a match is found
                LaunchedEffect(activeCall) {
                    if (activeCall != null) {
                        navController.navigate("call") {
                            launchSingleTop = true
                        }
                    }
                }

                NavHost(navController = navController, startDestination = "entry") {
                    composable("entry") {
                        EntryScreen(
                            viewModel = viewModel,
                            onGuestProceed = { navController.navigate("home") },
                            onPhoneAuth = { navController.navigate("phone_otp") }
                        )
                    }

                    composable("phone_otp") {
                        PhoneOtpScreen(
                            onVerified = { navController.navigate("home") }
                        )
                    }

                    composable("home") {
                        HomeScreen(
                            viewModel = viewModel,
                            onStartCall = { type ->
                                viewModel.startSearching(type)
                            },
                            onOpenChats = { navController.navigate("chats") },
                            onOpenCoins = { navController.navigate("coins") },
                            onOpenProfile = { navController.navigate("profile") },
                            onOpenSafety = { navController.navigate("safety") }
                        )
                    }

                    composable("call") {
                        CallScreen(
                            viewModel = viewModel,
                            onCallFinished = { navController.popBackStack("home", false) }
                        )
                    }

                    composable("chats") {
                        ChatsScreen(
                            onBack = { navController.popBackStack() }
                        )
                    }

                    composable("coins") {
                        CoinStoreScreen(
                            viewModel = viewModel,
                            onBack = { navController.popBackStack() }
                        )
                    }

                    composable("profile") {
                        ProfileScreen(
                            viewModel = viewModel,
                            onBack = { navController.popBackStack() },
                            onOpenCoins = { navController.navigate("coins") },
                            onOpenChats = { navController.navigate("chats") },
                            onOpenSafety = { navController.navigate("safety") },
                            onLoggedOut = {
                                navController.navigate("entry") {
                                    popUpTo(0)
                                }
                            }
                        )
                    }

                    composable("safety") {
                        SafetyScreen(
                            onBack = { navController.popBackStack() }
                        )
                    }
                }
            }
        }
    }
}
