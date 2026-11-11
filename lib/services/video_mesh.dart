import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config.dart';

/// Was ich an einen Mitspieler sende bzw. von ihm wiedergebe.
class MediaGate {
  const MediaGate(this.video, this.audio);
  final bool video;
  final bool audio;
  static const none = MediaGate(false, false);
  static const full = MediaGate(true, true);
  static const videoOnly = MediaGate(true, false);

  @override
  bool operator ==(Object other) => other is MediaGate && other.video == video && other.audio == audio;
  @override
  int get hashCode => Object.hash(video, audio);
}

class _Peer {
  _Peer(this.uid, this.sid, this.initiator);
  final String uid;
  final String sid;
  final bool initiator;
  String stamp = '';
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  MediaStream? stream;
  RTCRtpSender? videoSender;
  RTCRtpSender? audioSender;
  bool remoteSet = false;
  final List<RTCIceCandidate> pendingCandidates = [];
  MediaGate sent = MediaGate.full;
  bool connected = false;
  bool closed = false;
}

/// Vollvermaschtes WebRTC-Netz: jeder Spieler hat eine direkte Verbindung zu
/// jedem anderen. Die Signalisierung läuft über Firestore
/// (rooms/{code}/signals). Welche Bild-/Tonspur an wen geht, wird pro
/// Verbindung über [setSendPolicy] gesteuert – so sehen sich nachts nur die
/// Werwölfe.
class VideoMesh extends ChangeNotifier {
  VideoMesh({required this.code, required this.me});

  final String code;
  final String me;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  MediaStream? _local;
  final Map<String, _Peer> _peers = {};
  StreamSubscription? _signalSub;
  MediaGate Function(String peer) _sendPolicy = (_) => MediaGate.full;
  MediaGate Function(String peer) _playPolicy = (_) => MediaGate.full;
  bool _disposed = false;
  int _sidCounter = 0;

  String? cameraError;
  bool micMuted = false;
  bool cameraOff = false;
  bool get hasLocalVideo => _local != null && _local!.getVideoTracks().isNotEmpty;

  CollectionReference<Map<String, dynamic>> get _signals =>
      _db.collection('rooms').doc(code).collection('signals');

  RTCVideoRenderer? rendererFor(String uid) {
    final p = _peers[uid];
    if (p == null || p.stream == null) return null;
    return p.renderer;
  }

  bool isConnected(String uid) => _peers[uid]?.connected ?? false;

  Future<void> start() async {
    await localRenderer.initialize();
    try {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 480},
          'height': {'ideal': 360},
          'frameRate': {'ideal': 15, 'max': 20},
        },
      });
      localRenderer.srcObject = _local;
    } catch (e) {
      cameraError = 'Kamera oder Mikrofon nicht verfügbar. Du kannst trotzdem mitspielen.';
      debugPrint('getUserMedia: $e');
    }
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}

    // Alte Signale an mich wegräumen.
    final old = await _signals.where('to', isEqualTo: me).get();
    for (final d in old.docs) {
      d.reference.delete();
    }
    _signalSub = _signals.where('to', isEqualTo: me).snapshots().listen((q) {
      for (final c in q.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final data = c.doc.data();
        c.doc.reference.delete();
        if (data != null) _onSignal(data);
      }
    });
    notifyListeners();
  }

  /// Gleicht die Verbindungen mit der Spielerliste ab (uid -> stamp).
  void syncPeers(Map<String, String> players) {
    if (_disposed) return;
    for (final uid in _peers.keys.toList()) {
      if (!players.containsKey(uid)) _closePeer(uid);
    }
    players.forEach((uid, stamp) {
      if (uid == me) return;
      final existing = _peers[uid];
      if (existing != null) {
        if (existing.stamp.isNotEmpty && existing.stamp != stamp) {
          // Mitspieler ist neu beigetreten → Verbindung neu aufbauen.
          _closePeer(uid);
        } else {
          existing.stamp = stamp;
          return;
        }
      }
      // Der Spieler mit der kleineren uid ruft an.
      if (me.compareTo(uid) < 0) {
        _call(uid, stamp);
      }
    });
  }

  void setPolicies({
    required MediaGate Function(String peer) send,
    required MediaGate Function(String peer) play,
  }) {
    _sendPolicy = send;
    _playPolicy = play;
    for (final p in _peers.values) {
      _applyGate(p);
    }
  }

  MediaGate playGate(String uid) => _playPolicy(uid);

  Future<void> _applyGate(_Peer p) async {
    if (p.closed) return;
    final want = _sendPolicy(p.uid);
    if (want != p.sent) {
      p.sent = want;
      try {
        final v = _local?.getVideoTracks().firstOrNull;
        final a = _local?.getAudioTracks().firstOrNull;
        await p.videoSender?.replaceTrack(want.video ? v : null);
        await p.audioSender?.replaceTrack(want.audio ? a : null);
      } catch (e) {
        debugPrint('replaceTrack: $e');
      }
    }
    final play = _playPolicy(p.uid);
    for (final t in p.stream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = play.audio;
    }
  }

  Future<_Peer> _createPeer(String uid, String sid, bool initiator) async {
    final p = _Peer(uid, sid, initiator);
    _peers[uid] = p;
    await p.renderer.initialize();
    final pc = await createPeerConnection({
      'iceServers': kIceServers,
      'sdpSemantics': 'unified-plan',
    });
    p.pc = pc;

    final local = _local;
    final v = local?.getVideoTracks().firstOrNull;
    final a = local?.getAudioTracks().firstOrNull;
    if (a != null) {
      p.audioSender = await pc.addTrack(a, local!);
    } else {
      await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
    }
    if (v != null) {
      p.videoSender = await pc.addTrack(v, local!);
    } else {
      await pc.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
    }

    pc.onTrack = (RTCTrackEvent e) {
      if (p.closed) return;
      if (e.streams.isNotEmpty) {
        p.stream = e.streams.first;
        p.renderer.srcObject = p.stream;
        _applyGate(p);
        notifyListeners();
      }
    };
    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null || p.closed) return;
      _send(uid, {
        'type': 'candidate',
        'sid': sid,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (p.closed) return;
      p.connected = s == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      notifyListeners();
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed && p.initiator) {
        // Neuer Versuch nach kurzer Pause.
        final stamp = p.stamp;
        Future.delayed(const Duration(seconds: 3), () {
          if (_disposed || _peers[uid] != p) return;
          _closePeer(uid);
          _call(uid, stamp);
        });
      }
    };
    // Gate initial anwenden (z. B. falls man nachts beitritt).
    p.sent = MediaGate.full;
    await _applyGate(p);
    return p;
  }

  Future<void> _call(String uid, String stamp) async {
    final sid = '$me-${DateTime.now().millisecondsSinceEpoch}-${_sidCounter++}';
    final p = await _createPeer(uid, sid, true);
    p.stamp = stamp;
    final offer = await p.pc!.createOffer({});
    await p.pc!.setLocalDescription(offer);
    await _send(uid, {'type': 'offer', 'sid': sid, 'sdp': offer.sdp, 'sdpType': offer.type});
  }

  Future<void> _onSignal(Map<String, dynamic> s) async {
    if (_disposed) return;
    final from = s['from'] as String?;
    final sid = s['sid'] as String?;
    if (from == null || sid == null) return;
    try {
      switch (s['type']) {
        case 'offer':
          if (_peers.containsKey(from)) _closePeer(from);
          final p = await _createPeer(from, sid, false);
          await p.pc!.setRemoteDescription(RTCSessionDescription(s['sdp'] as String?, s['sdpType'] as String?));
          p.remoteSet = true;
          await _flush(p);
          final answer = await p.pc!.createAnswer({});
          await p.pc!.setLocalDescription(answer);
          await _send(from, {'type': 'answer', 'sid': sid, 'sdp': answer.sdp, 'sdpType': answer.type});
        case 'answer':
          final p = _peers[from];
          if (p == null || p.sid != sid || p.remoteSet) return;
          await p.pc!.setRemoteDescription(RTCSessionDescription(s['sdp'] as String?, s['sdpType'] as String?));
          p.remoteSet = true;
          await _flush(p);
        case 'candidate':
          final p = _peers[from];
          if (p == null || p.sid != sid) return;
          final c = RTCIceCandidate(
              s['candidate'] as String?, s['sdpMid'] as String?, (s['sdpMLineIndex'] as num?)?.toInt());
          if (p.remoteSet) {
            await p.pc!.addCandidate(c);
          } else {
            p.pendingCandidates.add(c);
          }
      }
    } catch (e) {
      debugPrint('Signal-Fehler: $e');
    }
  }

  Future<void> _flush(_Peer p) async {
    for (final c in p.pendingCandidates) {
      await p.pc!.addCandidate(c);
    }
    p.pendingCandidates.clear();
  }

  Future<void> _send(String to, Map<String, dynamic> data) => _signals.add({
        ...data,
        'from': me,
        'to': to,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

  void _closePeer(String uid) {
    final p = _peers.remove(uid);
    if (p == null) return;
    p.closed = true;
    p.renderer.srcObject = null;
    p.pc?.close();
    p.renderer.dispose();
    notifyListeners();
  }

  void toggleMic() {
    micMuted = !micMuted;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !micMuted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    cameraOff = !cameraOff;
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !cameraOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final t = _local?.getVideoTracks().firstOrNull;
    if (t == null) return;
    try {
      await Helper.switchCamera(t);
    } catch (e) {
      debugPrint('switchCamera: $e'); // z. B. am PC mit nur einer Webcam
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _signalSub?.cancel();
    for (final uid in _peers.keys.toList()) {
      _closePeer(uid);
    }
    for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      t.stop();
    }
    _local?.dispose();
    localRenderer.srcObject = null;
    localRenderer.dispose();
    super.dispose();
  }
}
