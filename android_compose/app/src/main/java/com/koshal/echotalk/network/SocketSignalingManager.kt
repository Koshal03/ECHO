package com.koshal.echotalk.network

import android.util.Log
import io.socket.client.IO
import io.socket.client.Socket
import org.json.JSONObject

class SocketSignalingManager {

    private var socket: Socket? = null
    private val TAG = "EchoSocket"

    var onMatched: ((roomId: String, isInitiator: Boolean, callType: String, strangerName: String, strangerId: String) -> Unit)? = null
    var onCallEnded: ((reason: String) -> Unit)? = null
    var onGuestExpired: ((message: String) -> Unit)? = null
    var onCoinsReceived: ((amount: Int, newBalance: Int, reason: String) -> Unit)? = null
    var onAdminBroadcast: ((message: String) -> Unit)? = null
    var onQueueStatus: ((status: String, position: Int) -> Unit)? = null

    var onWebRtcOffer: ((sdp: JSONObject) -> Unit)? = null
    var onWebRtcAnswer: ((sdp: JSONObject) -> Unit)? = null
    var onWebRtcIce: ((candidate: JSONObject) -> Unit)? = null

    fun connect(serverUrl: String) {
        try {
            val options = IO.Options.builder()
                .setTransports(arrayOf("websocket"))
                .build()

            socket = IO.socket(serverUrl, options)

            socket?.on(Socket.EVENT_CONNECT) {
                Log.d(TAG, "Connected to Flask WebRTC Signalling Server")
            }

            socket?.on("matched") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    val roomId = data.getString("roomId")
                    val isInitiator = data.getBoolean("isInitiator")
                    val callType = data.optString("callType", "audio")
                    val stranger = data.getJSONObject("stranger")
                    val strangerId = stranger.getString("id")
                    val strangerName = stranger.getString("displayName")

                    onMatched?.invoke(roomId, isInitiator, callType, strangerName, strangerId)
                }
            }

            socket?.on("queue-status") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    onQueueStatus?.invoke(data.optString("status"), data.optInt("queuePosition", 1))
                }
            }

            socket?.on("call-ended") { args ->
                val reason = if (args.isNotEmpty()) (args[0] as JSONObject).optString("reason", "Call ended") else "Call ended"
                onCallEnded?.invoke(reason)
            }

            socket?.on("guest-expired") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    onGuestExpired?.invoke(data.optString("message", "Guest time limit reached. Please sign up."))
                }
            }

            socket?.on("coins-received") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    onCoinsReceived?.invoke(data.getInt("amount"), data.getInt("newBalance"), data.optString("reason", "Gift"))
                }
            }

            socket?.on("admin-broadcast") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    onAdminBroadcast?.invoke(data.getString("message"))
                }
            }

            socket?.on("webrtc-offer") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    onWebRtcOffer?.invoke(data.getJSONObject("sdp"))
                }
            }

            socket?.on("webrtc-answer") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    onWebRtcAnswer?.invoke(data.getJSONObject("sdp"))
                }
            }

            socket?.on("webrtc-ice") { args ->
                if (args.isNotEmpty()) {
                    val data = args[0] as JSONObject
                    onWebRtcIce?.invoke(data.getJSONObject("candidate"))
                }
            }

            socket?.connect()
        } catch (e: Exception) {
            Log.e(TAG, "Socket connection failed", e)
        }
    }

    fun registerPresence(userId: String, displayName: String, isGuest: Boolean) {
        val json = JSONObject().apply {
            put("userId", userId)
            put("displayName", displayName)
            put("isGuest", isGuest)
        }
        socket?.emit("register-presence", json)
    }

    fun joinMatchingQueue(userId: String, displayName: String, callType: String, isGuest: Boolean, sessionId: String?) {
        val json = JSONObject().apply {
            put("userId", userId)
            put("displayName", displayName)
            put("callType", callType) // "audio" or "video"
            put("isGuest", isGuest)
            put("sessionId", sessionId)
        }
        socket?.emit("join-matching-queue", json)
    }

    fun leaveMatchingQueue() {
        socket?.emit("leave-matching-queue")
    }

    fun sendOffer(roomId: String, sdp: JSONObject) {
        val json = JSONObject().apply {
            put("roomId", roomId)
            put("sdp", sdp)
        }
        socket?.emit("webrtc-offer", json)
    }

    fun sendAnswer(roomId: String, sdp: JSONObject) {
        val json = JSONObject().apply {
            put("roomId", roomId)
            put("sdp", sdp)
        }
        socket?.emit("webrtc-answer", json)
    }

    fun sendIceCandidate(roomId: String, candidate: JSONObject) {
        val json = JSONObject().apply {
            put("roomId", roomId)
            put("candidate", candidate)
        }
        socket?.emit("webrtc-ice", json)
    }

    fun skipCall(roomId: String) {
        val json = JSONObject().apply {
            put("roomId", roomId)
        }
        socket?.emit("skip-call", json)
    }

    fun endCall(roomId: String) {
        val json = JSONObject().apply {
            put("roomId", roomId)
        }
        socket?.emit("end-call", json)
    }

    fun disconnect() {
        socket?.disconnect()
        socket?.off()
        socket = null
    }
}
