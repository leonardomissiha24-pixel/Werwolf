import 'dart:async';

import '../models/roles.dart';

/// Der maßgebliche Spielzustand. Lebt nur auf dem Gerät des Spielleiters;
/// jede Änderung wird gebündelt an alle Mitspieler verschickt.
class HostStore {
  HostStore({required this.hostId, required this.onFlush});

  final String hostId;

  /// Wird nach Änderungen aufgerufen: [secrets] enthält die geänderten Geheimnisse.
  final void Function(Set<String> changedSecrets) onFlush;

  late Map<String, dynamic> room = {
    'hostId': hostId,
    'phase': Phase.lobby,
    'round': 0,
    'narration': '',
    'narrationId': 0,
    'settings': {'roles': <String, int>{}, 'mayor': true, 'day': 180},
  };
  final Map<String, Map<String, dynamic>> players = {};
  final Map<String, Map<String, dynamic>> secrets = {};
  final Map<String, Map<String, dynamic>> actions = {};

  final _actionCtrl = StreamController<Map<String, Map<String, dynamic>>>.broadcast();
  Stream<Map<String, Map<String, dynamic>>> get actionStream => _actionCtrl.stream;

  final Set<String> _dirtySecrets = {};
  bool _scheduled = false;
  bool _disposed = false;

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_disposed) return;
      final s = {..._dirtySecrets};
      _dirtySecrets.clear();
      onFlush(s);
    });
  }

  void updateRoom(Map<String, dynamic> m) {
    room.addAll(m);
    _schedule();
  }

  void setPlayer(String uid, Map<String, dynamic> m) {
    players[uid] = m;
    _schedule();
  }

  void updatePlayer(String uid, Map<String, dynamic> m) {
    final p = players[uid];
    if (p == null) return;
    p.addAll(m);
    _schedule();
  }

  void removePlayer(String uid) {
    if (players.remove(uid) != null) _schedule();
  }

  /// Führt [m] in das Geheimnis von [uid] ein. `seen` wird ergänzt, alles andere ersetzt.
  void mergeSecret(String uid, Map<String, dynamic> m) {
    final s = secrets.putIfAbsent(uid, () => {});
    m.forEach((k, v) {
      if (k == 'seen' && v is Map && s[k] is Map) {
        s[k] = {...(s[k] as Map), ...v};
      } else {
        s[k] = v;
      }
    });
    _dirtySecrets.add(uid);
    _schedule();
  }

  void touchSecret(String uid) {
    _dirtySecrets.add(uid);
    _schedule();
  }

  void clearSecrets() {
    for (final uid in {...secrets.keys, ...players.keys}) {
      secrets[uid] = {};
      _dirtySecrets.add(uid);
    }
    _schedule();
  }

  void clearActions() {
    actions.clear();
  }

  /// Aktion eines Spielers (Nachtaktion, Stimme …).
  void putAction(String uid, Map<String, dynamic> data) {
    if (!players.containsKey(uid)) return;
    actions[uid] = data;
    if (!_actionCtrl.isClosed) _actionCtrl.add(actions);
  }

  void resetToLobby() {
    clearActions();
    clearSecrets();
    for (final p in players.values) {
      p.addAll({'alive': true, 'role': null, 'mayor': false, 'canVote': true, 'lover': false});
    }
    updateRoom({
      'phase': Phase.lobby,
      'step': null,
      'round': 0,
      'endsAt': null,
      'narration': '',
      'actionKey': '',
      'actor': null,
      'winner': null,
      'winners': <String>[],
      'tally': <String, int>{},
    });
  }

  void dispose() {
    _disposed = true;
    _actionCtrl.close();
  }
}
