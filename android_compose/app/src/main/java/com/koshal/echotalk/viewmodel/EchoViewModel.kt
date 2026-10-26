package com.koshal.echotalk.viewmodel

import android.app.Application
import android.os.CountDownTimer
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.koshal.echotalk.data.model.*
import com.koshal.echotalk.network.EchoApiService
import com.koshal.echotalk.network.SocketSignalingManager
import com.koshal.echotalk.webrtc.WebRtcCallEngine
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

class EchoViewModel(application: Application) : AndroidViewModel(application) {

    private val api = EchoApiService.create()
    val socketManager = SocketSignalingManager()
    var webrtcEngine: WebRtcCallEngine? = null

    // UI State flows
    private val _currentUser = MutableStateFlow<UserModel?>(null)
    val currentUser: StateFlow<UserModel?> = _currentUser.asStateFlow()

    private val _guestTotalSeconds = MutableStateFlow(3600) // 60 mins
    val guestTotalSeconds: StateFlow<Int> = _guestTotalSeconds.asStateFlow()

    private val _guestVideoSeconds = MutableStateFlow(1800) // 30 mins
    val guestVideoSeconds: StateFlow<Int> = _guestVideoSeconds.asStateFlow()

    private val _systemSettings = MutableStateFlow(SystemSettings())
    val systemSettings: StateFlow<SystemSettings> = _systemSettings.asStateFlow()

    private val _iceServers = MutableStateFlow<List<IceServerConfig>>(emptyList())

    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    private val _activeCall = MutableStateFlow<CallSession?>(null)
    val activeCall: StateFlow<CallSession?> = _activeCall.asStateFlow()

    private val _broadcastAlert = MutableStateFlow<String?>(null)
    val broadcastAlert: StateFlow<String?> = _broadcastAlert.asStateFlow()

    private val _giftCoinsAlert = MutableStateFlow<String?>(null)
    val giftCoinsAlert: StateFlow<String?> = _giftCoinsAlert.asStateFlow()

    private val _showGuestExpiredNotice = MutableStateFlow(false)
    val showGuestExpiredNotice: StateFlow<Boolean> = _showGuestExpiredNotice.asStateFlow()

    private var guestTimer: CountDownTimer? = null
    private var lastInterstitialShownTime: Long = 0L

    init {
        loadConfig()
        setupSocketListeners()
    }

    private fun loadConfig() {
        viewModelScope.launch {
            try {
                val res = api.getConfig()
                if (res.isSuccessful && res.body() != null) {
                    val body = res.body()!!
                    _systemSettings.value = body.settings
                    _iceServers.value = body.ice_servers
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun setupSocketListeners() {
        socketManager.connect(EchoApiService.BASE_URL)

        socketManager.onMatched = { roomId, isInitiator, callType, strangerName, strangerId ->
            _isSearching.value = false
            _activeCall.value = CallSession(
                roomId = roomId,
                strangerId = strangerId,
                strangerName = strangerName,
                isInitiator = isInitiator,
                callType = callType
            )

            // Setup WebRTC
            webrtcEngine = WebRtcCallEngine(getApplication()).apply {
                onIceCandidateGenerated = { candidate ->
                    socketManager.sendIceCandidate(roomId, candidate)
                }
            }
            webrtcEngine?.createPeerConnection(_iceServers.value)

            if (isInitiator) {
                webrtcEngine?.createOffer { offer ->
                    socketManager.sendOffer(roomId, offer)
                }
            }
        }

        socketManager.onWebRtcOffer = { sdp ->
            webrtcEngine?.handleOfferAndCreateAnswer(sdp) { answer ->
                _activeCall.value?.roomId?.let { rId ->
                    socketManager.sendAnswer(rId, answer)
                }
            }
        }

        socketManager.onWebRtcAnswer = { sdp ->
            webrtcEngine?.handleAnswer(sdp)
        }

        socketManager.onWebRtcIce = { candidate ->
            webrtcEngine?.addRemoteIceCandidate(candidate)
        }

        socketManager.onCallEnded = {
            endCallInternal()
        }

        socketManager.onGuestExpired = {
            _showGuestExpiredNotice.value = true
        }

        socketManager.onCoinsReceived = { amount, newBal, _ ->
            _currentUser.value?.coins = newBal
            _giftCoinsAlert.value = "You received +$amount bonus coins from Moderator!"
        }

        socketManager.onAdminBroadcast = { msg ->
            _broadcastAlert.value = msg
        }
    }

    // 1. Guest Session
    fun loginAsGuest() {
        viewModelScope.launch {
            try {
                val res = api.initGuest(emptyMap())
                if (res.isSuccessful && res.body() != null) {
                    val obj = res.body()!!
                    val sess = obj.getAsJsonObject("session")
                    val totalSec = obj.get("totalSecondsRemaining").asInt
                    val videoSec = obj.get("videoSecondsRemaining").asInt

                    _guestTotalSeconds.value = totalSec
                    _guestVideoSeconds.value = videoSec

                    val guestUser = UserModel(
                        userId = sess.get("sessionId").asString,
                        username = sess.get("displayName").asString,
                        displayName = sess.get("displayName").asString,
                        coins = sess.get("coins").asInt,
                        isGuest = true
                    )
                    _currentUser.value = guestUser

                    socketManager.registerPresence(guestUser.userId, guestUser.displayName, true)
                    startGuestCountdown(totalSec)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun startGuestCountdown(totalSeconds: Int) {
        guestTimer?.cancel()
        guestTimer = object : CountDownTimer((totalSeconds * 1000).toLong(), 1000) {
            override fun onTick(millisUntilFinished: Long) {
                _guestTotalSeconds.value = (millisUntilFinished / 1000).toInt()
            }

            override fun onFinish() {
                _guestTotalSeconds.value = 0
                _showGuestExpiredNotice.value = true
            }
        }.start()
    }

    // 2. Queue & Calling
    fun startSearching(callType: String) { // "audio" or "video"
        val user = _currentUser.value ?: return
        _isSearching.value = true

        socketManager.joinMatchingQueue(
            userId = user.userId,
            displayName = user.displayName,
            callType = callType,
            isGuest = user.isGuest,
            sessionId = if (user.isGuest) user.userId else null
        )
    }

    fun cancelSearch() {
        _isSearching.value = false
        socketManager.leaveMatchingQueue()
    }

    fun skipCall() {
        _activeCall.value?.let { call ->
            socketManager.skipCall(call.roomId)
            val type = call.callType
            endCallInternal()
            startSearching(type)
        }
    }

    fun endCall() {
        _activeCall.value?.let { call ->
            socketManager.endCall(call.roomId)
            endCallInternal()
        }
    }

    private fun endCallInternal() {
        webrtcEngine?.close()
        webrtcEngine = null
        _activeCall.value = null

        // Check AdMob 2-minute Interstitial Cooldown rule
        val now = System.currentTimeMillis()
        val cooldownMs = _systemSettings.value.interstitial_cooldown_seconds * 1000L
        if (_systemSettings.value.ads_interstitial_enabled && (now - lastInterstitialShownTime >= cooldownMs)) {
            lastInterstitialShownTime = now
            // Trigger AdMob Interstitial Ad on UI
        }
    }

    // 3. Safety: Report & Block
    fun reportAndBlockUser(category: String, desc: String) {
        val strangerId = _activeCall.value?.strangerId ?: return
        val currentUserId = _currentUser.value?.userId ?: return

        viewModelScope.launch {
            try {
                api.submitReport(mapOf(
                    "reporterId" to currentUserId,
                    "reportedUserId" to strangerId,
                    "category" to category,
                    "description" to desc
                ))
                api.blockUser(mapOf(
                    "blockerId" to currentUserId,
                    "blockedUserId" to strangerId
                ))
            } catch (_: Exception) {}
        }
        endCall()
    }

    // 4. Delete Account (Play Store Compliance)
    fun deleteMyAccount(onComplete: () -> Unit) {
        val user = _currentUser.value ?: return
        viewModelScope.launch {
            try {
                api.deleteAccount(mapOf("userId" to user.userId))
                _currentUser.value = null
                onComplete()
            } catch (_: Exception) {}
        }
    }

    // 5. Coins & Wallet
    fun addCoins(amount: Int) {
        _currentUser.value?.let { u ->
            u.coins += amount
            _currentUser.value = u.copy(coins = u.coins)
        }
    }

    fun dismissBroadcastAlert() {
        _broadcastAlert.value = null
    }

    fun dismissGiftCoinsAlert() {
        _giftCoinsAlert.value = null
    }

    override fun onCleared() {
        super.onCleared()
        guestTimer?.cancel()
        webrtcEngine?.close()
        socketManager.disconnect()
    }
}
