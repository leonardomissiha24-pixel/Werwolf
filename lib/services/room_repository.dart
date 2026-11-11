import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_state.dart';
import '../models/roles.dart';

class RoomException implements Exception {
  RoomException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Kapselt alle Firestore-Zugriffe der Clients.
class RoomRepository {
  RoomRepository._();
  static final instance = RoomRepository._();

  final FirebaseFirestore db = FirebaseFirestore.instance;
  final _rnd = Random.secure();

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> ensureSignedIn() async {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  }

  DocumentReference<Map<String, dynamic>> room(String code) => db.collection('rooms').doc(code);

  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(5, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  String newStamp() => List.generate(8, (_) => _rnd.nextInt(36).toRadixString(36)).join();

  int get _expires => DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;

  Future<String> createRoom(String name) async {
    await ensureSignedIn();
    for (var i = 0; i < 8; i++) {
      final code = _newCode();
      final ref = room(code);
      final created = await db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) return false;
        tx.set(ref, {
          'hostId': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromMillisecondsSinceEpoch(_expires),
          'phase': Phase.lobby,
          'round': 0,
          'narration': '',
          'narrationId': 0,
          'settings': {'roles': <String, int>{}, 'mayor': true, 'day': 180},
        });
        return true;
      });
      if (created) {
        await _writePlayer(code, name, create: true);
        return code;
      }
    }
    throw RoomException('Konnte keinen freien Raumcode finden.');
  }

  Future<void> joinRoom(String code, String name) async {
    await ensureSignedIn();
    final snap = await room(code).get();
    if (!snap.exists) throw RoomException('Dieses Dorf existiert nicht.');
    final data = snap.data()!;
    if (data['closed'] == true) throw RoomException('Dieses Dorf wurde verlassen.');
    final me = await room(code).collection('players').doc(uid).get();
    if (me.exists) {
      await room(code).collection('players').doc(uid).update({'stamp': newStamp()});
      return;
    }
    if (data['phase'] != Phase.lobby) {
      throw RoomException('Das Spiel in diesem Dorf hat bereits begonnen.');
    }
    final count = (await room(code).collection('players').count().get()).count ?? 0;
    if (count >= maxPlayers) throw RoomException('Das Dorf ist voll ($maxPlayers Spieler).');
    await _writePlayer(code, name, create: true);
  }

  static const maxPlayers = 12;

  Future<void> _writePlayer(String code, String name, {required bool create}) async {
    await room(code).collection('players').doc(uid).set({
      'name': name,
      'stamp': newStamp(),
      'joinedAt': DateTime.now().millisecondsSinceEpoch,
      'alive': true,
      'mayor': false,
      'canVote': true,
      'expiresAt': Timestamp.fromMillisecondsSinceEpoch(_expires),
    });
  }

  Future<void> leaveRoom(String code, {required bool isHost, required bool inLobby}) async {
    try {
      if (isHost) {
        await room(code).update({'closed': true});
      }
      if (inLobby || isHost) {
        await room(code).collection('players').doc(uid).delete();
      }
    } catch (_) {
      // Offline o.ä. – egal, der Raum verfällt ohnehin.
    }
  }

  Stream<RoomState?> watchRoom(String code) => room(code)
      .snapshots()
      .map((s) => s.exists ? RoomState(code, s.data()!) : null);

  Stream<List<PlayerState>> watchPlayers(String code) =>
      room(code).collection('players').snapshots().map((q) {
        final list = q.docs.map((d) => PlayerState(d.id, d.data())).toList()
          ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
        return list;
      });

  Stream<SecretState> watchSecret(String code) => room(code)
      .collection('secrets')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? SecretState(s.data()!) : SecretState.empty());

  Future<void> updateSettings(String code, Map<String, int> roles, bool mayor, int day) =>
      room(code).update({
        'settings': {'roles': roles, 'mayor': mayor, 'day': day},
      });

  /// Schreibt die Aktion des Spielers für die aktuelle Phase.
  Future<void> submitAction(String code, String key, Map<String, dynamic> data) =>
      room(code).collection('actions').doc(uid).set({
        ...data,
        'key': key,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'expiresAt': Timestamp.fromMillisecondsSinceEpoch(_expires),
      });

  Stream<Map<String, dynamic>?> watchMyAction(String code) => room(code)
      .collection('actions')
      .doc(uid)
      .snapshots()
      .map((s) => s.data());
}
