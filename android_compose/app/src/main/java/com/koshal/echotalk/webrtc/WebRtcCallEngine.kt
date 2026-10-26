package com.koshal.echotalk.webrtc

import android.content.Context
import android.util.Log
import com.koshal.echotalk.data.model.IceServerConfig
import org.json.JSONObject
import org.webrtc.*

class WebRtcCallEngine(private val context: Context) {

    private val TAG = "EchoWebRTC"
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null

    private var localAudioTrack: AudioTrack? = null
    private var localVideoTrack: VideoTrack? = null
    private var videoCapturer: VideoCapturer? = null
    private var surfaceTextureHelper: SurfaceTextureHelper? = null

    var isMicMuted = false
        private set
    var isCameraOff = false
        private set

    var onIceCandidateGenerated: ((JSONObject) -> Unit)? = null
    var onRemoteStreamAvailable: ((MediaStream) -> Unit)? = null
    var onCallStateChange: ((PeerConnection.PeerConnectionState) -> Unit)? = null

    init {
        initializeFactory()
    }

    private fun initializeFactory() {
        val options = PeerConnectionFactory.InitializationOptions.builder(context)
            .setEnableInternalTracer(true)
            .createInitializationOptions()
        PeerConnectionFactory.initialize(options)

        peerConnectionFactory = PeerConnectionFactory.builder()
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(EglBase.create().eglBaseContext))
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(EglBase.create().eglBaseContext, true, true))
            .createPeerConnectionFactory()
    }

    fun startLocalMedia(isAudioOnly: Boolean, eglBaseContext: EglBase.Context) {
        // 1. Audio Source
        val audioSource = peerConnectionFactory?.createAudioSource(MediaConstraints())
        localAudioTrack = peerConnectionFactory?.createAudioTrack("ARDAMSa0", audioSource)

        // 2. Video Source (if not audio only)
        if (!isAudioOnly) {
            surfaceTextureHelper = SurfaceTextureHelper.create("CaptureThread", eglBaseContext)
            val videoSource = peerConnectionFactory?.createVideoSource(false)
            videoCapturer = createCameraCapturer()
            videoCapturer?.initialize(surfaceTextureHelper, context, videoSource?.capturerObserver)
            videoCapturer?.startCapture(640, 480, 30)
            localVideoTrack = peerConnectionFactory?.createVideoTrack("ARDAMSv0", videoSource)
        }
    }

    private fun createCameraCapturer(): VideoCapturer? {
        val enumerator = Camera2Enumerator(context)
        val deviceNames = enumerator.deviceNames
        // Find front camera
        for (deviceName in deviceNames) {
            if (enumerator.isFrontFacing(deviceName)) {
                return enumerator.createCapturer(deviceName, null)
            }
        }
        // Fallback to back camera
        for (deviceName in deviceNames) {
            if (enumerator.isBackFacing(deviceName)) {
                return enumerator.createCapturer(deviceName, null)
            }
        }
        return null
    }

    fun createPeerConnection(iceConfigs: List<IceServerConfig>) {
        val iceServers = mutableListOf<PeerConnection.IceServer>()
        iceServers.add(PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer())

        iceConfigs.forEach { cfg ->
            val builder = PeerConnection.IceServer.builder(cfg.urls)
            if (!cfg.username.isNullOrEmpty() && !cfg.credential.isNullOrEmpty()) {
                builder.setUsername(cfg.username)
                builder.setPassword(cfg.credential)
            }
            iceServers.add(builder.createIceServer())
        }

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.DISABLED
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
        }

        peerConnection = peerConnectionFactory?.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate?) {
                candidate?.let {
                    val json = JSONObject().apply {
                        put("candidate", it.sdp)
                        put("sdpMid", it.sdpMid)
                        put("sdpMLineIndex", it.sdpMLineIndex)
                    }
                    onIceCandidateGenerated?.invoke(json)
                }
            }

            override fun onAddStream(stream: MediaStream?) {
                stream?.let { onRemoteStreamAvailable?.invoke(it) }
            }

            override fun onConnectionChange(newState: PeerConnection.PeerConnectionState?) {
                newState?.let { onCallStateChange?.invoke(it) }
            }

            override fun onSignalingChange(state: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {}
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {}
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onRemoveStream(stream: MediaStream?) {}
            override fun onDataChannel(channel: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
        })

        // Add local tracks
        localAudioTrack?.let { peerConnection?.addTrack(it) }
        localVideoTrack?.let { peerConnection?.addTrack(it) }
    }

    fun createOffer(callback: (JSONObject) -> Unit) {
        val sdpConstraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
        }

        peerConnection?.createOffer(object : SdpObserver {
            override fun onCreateSuccess(desc: SessionDescription?) {
                desc?.let {
                    peerConnection?.setLocalDescription(this, it)
                    val json = JSONObject().apply {
                        put("type", it.type.canonicalForm())
                        put("sdp", it.description)
                    }
                    callback(json)
                }
            }
            override fun onSetSuccess() {}
            override fun onCreateFailure(s: String?) { Log.e(TAG, "Offer creation failed: $s") }
            override fun onSetFailure(s: String?) {}
        }, sdpConstraints)
    }

    fun handleOfferAndCreateAnswer(offerJson: JSONObject, callback: (JSONObject) -> Unit) {
        val sdpType = SessionDescription.Type.fromCanonicalForm(offerJson.getString("type"))
        val description = SessionDescription(sdpType, offerJson.getString("sdp"))

        peerConnection?.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                val sdpConstraints = MediaConstraints().apply {
                    mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
                    mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
                }
                peerConnection?.createAnswer(object : SdpObserver {
                    override fun onCreateSuccess(desc: SessionDescription?) {
                        desc?.let {
                            peerConnection?.setLocalDescription(this, it)
                            val answerJson = JSONObject().apply {
                                put("type", it.type.canonicalForm())
                                put("sdp", it.description)
                            }
                            callback(answerJson)
                        }
                    }
                    override fun onSetSuccess() {}
                    override fun onCreateFailure(s: String?) {}
                    override fun onSetFailure(s: String?) {}
                }, sdpConstraints)
            }
            override fun onCreateSuccess(p0: SessionDescription?) {}
            override fun onCreateFailure(p0: String?) {}
            override fun onSetFailure(p0: String?) {}
        }, description)
    }

    fun handleAnswer(answerJson: JSONObject) {
        val sdpType = SessionDescription.Type.fromCanonicalForm(answerJson.getString("type"))
        val description = SessionDescription(sdpType, answerJson.getString("sdp"))
        peerConnection?.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() { Log.d(TAG, "Remote answer set successfully") }
            override fun onCreateSuccess(p0: SessionDescription?) {}
            override fun onCreateFailure(p0: String?) {}
            override fun onSetFailure(p0: String?) {}
        }, description)
    }

    fun addRemoteIceCandidate(candidateJson: JSONObject) {
        val candidate = IceCandidate(
            candidateJson.getString("sdpMid"),
            candidateJson.getInt("sdpMLineIndex"),
            candidateJson.getString("candidate")
        )
        peerConnection?.addIceCandidate(candidate)
    }

    fun toggleMute() {
        localAudioTrack?.let {
            isMicMuted = !isMicMuted
            it.setEnabled(!isMicMuted)
        }
    }

    fun toggleCamera() {
        localVideoTrack?.let {
            isCameraOff = !isCameraOff
            it.setEnabled(!isCameraOff)
        }
    }

    fun close() {
        try {
            videoCapturer?.stopCapture()
            videoCapturer?.dispose()
            surfaceTextureHelper?.dispose()
            localAudioTrack?.dispose()
            localVideoTrack?.dispose()
            peerConnection?.close()
            peerConnection?.dispose()
        } catch (e: Exception) {
            Log.e(TAG, "Cleanup exception", e)
        }
    }
}
