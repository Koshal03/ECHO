import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRtcService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  Function(RTCIceCandidate candidate)? onIceCandidate;
  Function(MediaStream stream)? onRemoteStreamAdded;
  Function(RTCPeerConnectionState state)? onConnectionStateChange;
  Function(RTCIceConnectionState state)? onIceConnectionStateChange;

  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _wantVideo = false;
  bool _cameraOff = false;
  bool _hasLocalVideo = false;
  bool _renderersReady = false;

  /// Video surfaces for the UI (only used in video calls).
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool get cameraOff => _cameraOff;
  bool get hasLocalVideo => _hasLocalVideo;

  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  /// Replace the STUN-only defaults with the server's list (adds TURN so calls
  /// connect on strict mobile networks).
  void setIceServers(List<dynamic> servers) {
    if (servers.isNotEmpty) _iceServers = {'iceServers': servers};
  }

  Map<String, dynamic> get _config => {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': _wantVideo,
        },
        'optional': [],
      };

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<void> initAudio() => initMedia(video: false);

  /// Opens the microphone (and the camera for video calls). If the camera is not
  /// available / permission was denied, the call continues with audio only.
  /// Returns false when the microphone could not be opened (the call cannot work then).
  Future<bool> initMedia({required bool video}) async {
    _wantVideo = video;
    _cameraOff = false;
    _hasLocalVideo = false;
    final Map<String, dynamic> audio = {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    };
    if (video) await _ensureRenderers();
    var gotAudio = false;
    try {
      if (video) {
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': audio,
            'video': {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            },
          });
          _hasLocalVideo = _localStream!.getVideoTracks().isNotEmpty;
        } catch (e) {
          debugPrint('[WEBRTC] camera unavailable, falling back to audio only: $e');
          _localStream = await navigator.mediaDevices.getUserMedia({'audio': audio, 'video': false});
        }
        localRenderer.srcObject = _hasLocalVideo ? _localStream : null;
      } else {
        _localStream = await navigator.mediaDevices.getUserMedia({'audio': audio, 'video': false});
      }
      gotAudio = _localStream != null && _localStream!.getAudioTracks().isNotEmpty;
      try {
        await Helper.setSpeakerphoneOn(_isSpeakerOn); // make the speaker button match the real audio route
      } catch (e) {
        debugPrint('[WEBRTC] could not set the speaker route: $e');
      }
      debugPrint('[WEBRTC] Local media acquired (audio: $gotAudio, video: $_hasLocalVideo)');
    } catch (e) {
      debugPrint('[WEBRTC ERROR] acquiring media: $e');
    }
    return gotAudio;
  }

  /// Returns false if the connection object could not be created.
  Future<bool> createPeerConnectionInstance() async {
    try {
      _peerConnection = await createPeerConnection(_iceServers, _config);

      // Add local audio tracks to peer connection
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate != null) {
          onIceCandidate?.call(candidate);
        }
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          if (_wantVideo && _renderersReady) remoteRenderer.srcObject = _remoteStream;
          onRemoteStreamAdded?.call(_remoteStream!);
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('[WEBRTC] Connection state changed: $state');
        onConnectionStateChange?.call(state);
      };

      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('[WEBRTC] ICE state changed: $state');
        onIceConnectionStateChange?.call(state);
      };
      return true;
    } catch (e) {
      debugPrint('[WEBRTC ERROR] creating peer connection: $e');
      return false;
    }
  }

  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer(_config);
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _peerConnection!.createAnswer(_config);
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(String sdp, String type) async {
    final pc = _peerConnection;
    if (pc == null) throw StateError('peer connection not ready');
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
  }

  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    final candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );
    final pc = _peerConnection;
    if (pc == null) throw StateError('peer connection not ready');
    await pc.addCandidate(candidate);
  }

  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final track = audioTracks[0];
        _isMuted = !_isMuted;
        track.enabled = !_isMuted;
      }
    }
  }

  /// Turns your camera on/off during a video call (the other side sees a frozen/black frame).
  void toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    _cameraOff = !_cameraOff;
    tracks[0].enabled = !_cameraOff;
  }

  /// Front <-> back camera.
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks[0]);
    } catch (e) {
      debugPrint('[WEBRTC] switchCamera failed: $e');
    }
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  Future<void> cleanUp() async {
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
      _localStream = null;

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;
      _remoteStream = null;
      if (_renderersReady) {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
      }
      _wantVideo = false;
      _cameraOff = false;
      _hasLocalVideo = false;
      _isMuted = false;
      _isSpeakerOn = true;
    } catch (e) {
      debugPrint('[WEBRTC CLEANUP ERROR] $e');
    }
  }
}
