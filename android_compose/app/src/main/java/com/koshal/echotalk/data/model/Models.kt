package com.koshal.echotalk.data.model

data class UserModel(
    val userId: String,
    val username: String,
    val displayName: String,
    val phone: String? = null,
    val avatarUrl: String = "",
    var coins: Int = 50,
    val isGuest: Boolean = false,
    val status: String = "active"
)

data class GuestSession(
    val sessionId: String,
    val displayName: String,
    val avatarUrl: String,
    val createdAt: Long,
    val expiresAt: Long,
    var videoSecondsRemaining: Int,
    var coins: Int,
    val isGuest: Boolean = true
)

data class CallSession(
    val roomId: String,
    val strangerId: String,
    val strangerName: String,
    val isInitiator: Boolean,
    val callType: String = "audio", // "audio" or "video"
    val startedAt: Long = System.currentTimeMillis()
)

data class VirtualGift(
    val id: String,
    val name: String,
    val icon: String,
    val coins: Int
) {
    companion object {
        val GIFTS = listOf(
            VirtualGift("gift_heart", "Heart", "❤️", 10),
            VirtualGift("gift_rose", "Virtual Rose", "🌹", 20),
            VirtualGift("gift_rocket", "Party Rocket", "🚀", 50),
            VirtualGift("gift_diamond", "Diamond", "💎", 100),
            VirtualGift("frame_neon", "Profile Frame", "🖼️", 250),
            VirtualGift("badge_vip", "VIP Crown Badge", "👑", 300)
        )
    }
}

data class CoinPack(
    val id: String,
    val name: String,
    val coins: Int,
    val priceFormatted: String,
    val description: String,
    val isPopular: Boolean = false
) {
    companion object {
        val PACKS = listOf(
            CoinPack("coins_50", "50 Coins", 50, "₹49", "Starter pack for gifts and flair"),
            CoinPack("coins_200", "200 Coins", 200, "₹149", "Most popular! Best value pack.", isPopular = true),
            CoinPack("coins_500", "500 Coins", 500, "₹299", "Heavy user coin pack"),
            CoinPack("coins_1200", "1,200 Coins", 1200, "₹499", "Maximum savings mega coin pack")
        )
    }
}

data class ConfigResponse(
    val settings: SystemSettings,
    val ice_servers: List<IceServerConfig>
)

data class SystemSettings(
    val guest_access_enabled: Boolean = true,
    val sign_up_enabled: Boolean = true,
    val audio_calls_enabled: Boolean = true,
    val video_calls_enabled: Boolean = true,
    val maintenance_mode: Boolean = false,
    val guest_total_limit_minutes: Int = 60,
    val guest_video_limit_minutes: Int = 30,
    val banner_message: String = "",
    val ads_banner_enabled: Boolean = true,
    val ads_interstitial_enabled: Boolean = true,
    val ads_rewarded_enabled: Boolean = true,
    val interstitial_cooldown_seconds: Int = 120
)

data class IceServerConfig(
    val urls: String,
    val username: String? = null,
    val credential: String? = null
)
