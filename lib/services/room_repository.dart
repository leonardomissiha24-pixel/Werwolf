import 'dart:async';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/game_state.dart';
import '../models/roles.dart';
import '../net/crypto.dart';
import '../net/host_store.dart';
import '../net/mqtt_transport.dart';
import '../net/transport.dart';

class RoomException implements Exception {
  RoomException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Hält den zuletzt bekannten Wert und liefert ihn jedem neuen Zuhörer sofort.
class _Latest<T> {
  final _ctrl = StreamController<T>.broadcast();
  T? _value;
  bool _has = false;

  T? get value => _value;

  void add(T v) {
    _value = v;
    _has = true;
    if (!_ctrl.isClosed) _ctrl.add(v);
  }

  Stream<T> get stream => Stream.multi((c) {
        if (_has) c.add(_value as T);
        final sub = _ctrl.stream.listen(c.add);
        c.onCancel = sub.cancel;
      });

  void close() => _ctrl.close();
}

/// Verbindung eines Geräts zu einem Dorf.
///
/// Es gibt keinen eigenen Spielserver: Das Gerät des Spielleiters hält den
/// Spielzustand ([HostStore]) und verteilt ihn verschlüsselt über einen
/// öffentlichen Vermittlungsserver. Rollen und Nachtaktionen sind zusätzlich
/// mit einem Schlüssel verschlüsselt, den nur Spielleiter und Spieler kennen.
class RoomRepository {
  RoomRepository({required this.uid, List<Transport Function()>? transports, this.joinTimeout = const Duration(seconds: 4)})
      : _factories = transports ?? [for (final b in kBrokers) () => MqttTransport(b)];

  static late RoomRepository instance;

  static String randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  static const maxPlayers = 12;

  final String uid;
  final List<Transport Function()> _factories;
  final Duration joinTimeout;
  final _rnd = Random.secure();

  Transport? _t;
  StreamSubscription? _msgSub, _reSub;
  String? _code;
  String _ch = '';
  SecretKey? _roomKey;
  SimpleKeyPair? _pair;
  String _myPub = '';
  String _name = '';
  String _stamp = '';
  Timer? _beat;
  Future<void> _out = Future.value();

  // --- nur Spielleiter ---
  HostStore? hostStore;
  final Map<String, String> _pubs = {};
  final Map<String, SecretKey> _shared = {};
  final Map<String, int> _lastSeen = {};

  // --- nur Mitspieler ---
  String? _hostPub;
  SecretKey? _hostShared;
  String? _rawSecret;

  var _room = _Latest<RoomState?>();
  var _players = _Latest<List<PlayerState>>();
  var _secret = _Latest<SecretState>();
  var _myAction = _Latest<Map<String, dynamic>?>();
  var _signals = StreamController<Map<String, dynamic>>.broadcast();

  bool get isHost => hostStore != null;

  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(5, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }

  String newStamp() => List.generate(8, (_) => _rnd.nextInt(36).toRadixString(36)).join();

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ------------------------------------------------------------------
  // Verbinden
  // ------------------------------------------------------------------

  Future<void> _prepare(String code, String name) async {
    final r = await Crypto.forRoom(code);
    _code = code;
    _ch = r.channel;
    _roomKey = r.key;
    _pair ??= await Crypto.newKeyPair();
    _myPub = await Crypto.publicKeyOf(_pair!);
    _name = name.length > 16 ? name.substring(0, 16) : name;
    _stamp = newStamp();
  }

  void _listen(Transport t) {
    _t = t;
    _msgSub = t.messages.asyncMap(_handle).listen((_) {}, onError: (Object e) => debugPrint('Netz: $e'));
    _reSub = t.reconnected.listen((_) => _onReconnected());
  }

  Future<String> createRoom(String name) async {
    await _reset();
    Transport? t;
    for (final f in _factories) {
      final c = f();
      try {
        await c.connect();
        t = c;
        break;
      } catch (e) {
        debugPrint('$e');
      }
    }
    if (t == null) {
      throw RoomException('Kein Vermittlungsserver erreichbar. Prüfe deine Internetverbindung.');
    }

    // Freien Code suchen: ein Dorf mit diesem Code darf nicht schon bestehen.
    for (var i = 0; i < 8; i++) {
      final code = _newCode();
      final r = await Crypto.forRoom(code);
      final topic = '${r.channel}/state';
      var taken = false;
      final sub = t.messages.where((m) => m.topic == topic).listen((m) async {
        final s = await Crypto.open(r.key, m.payload);
        if (s != null && (s['room'] as Map?)?['closed'] != true) taken = true;
      });
      t.subscribe(topic);
      await Future<void>.delayed(joinTimeout ~/ 3);
      await sub.cancel();
      if (taken) continue;

      await _prepare(code, name);
      final store = hostStore = HostStore(hostId: uid, onFlush: _hostFlush);
      _pubs[uid] = _myPub;
      _listen(t);
      t.subscribe('$_ch/join/+');
      t.subscribe('$_ch/leave/+');
      t.subscribe('$_ch/action/+');
      t.subscribe('$_ch/signal/$uid');
      store.setPlayer(uid, _newPlayer(_name, _stamp));
      _beat = Timer.periodic(const Duration(seconds: 5), (_) => _pruneLobby());
      return code;
    }
    await t.disconnect();
    throw RoomException('Konnte keinen freien Dorfcode finden.');
  }

  Map<String, dynamic> _newPlayer(String name, String stamp) => {
        'name': name,
        'stamp': stamp,
        'joinedAt': _now,
        'alive': true,
        'mayor': false,
        'canVote': true,
      };

  Future<void> joinRoom(String code, String name) async {
    await _reset();
    await _prepare(code, name);
    var anyBroker = false;
    for (final f in _factories) {
      final t = f();
      try {
        await t.connect();
      } catch (e) {
        debugPrint('$e');
        continue;
      }
      anyBroker = true;
      _listen(t);
      t.subscribe('$_ch/state');
      t.subscribe('$_ch/secret/$uid');
      t.subscribe('$_ch/signal/$uid');
      final found = await _waitFor(() => _room.value != null, joinTimeout);
      if (found) break;
      await _msgSub?.cancel();
      await _reSub?.cancel();
      await t.disconnect();
      _t = null;
    }
    if (_t == null) {
      await _reset();
      throw RoomException(anyBroker
          ? 'Dieses Dorf existiert nicht.'
          : 'Kein Vermittlungsserver erreichbar. Prüfe deine Internetverbindung.');
    }
    final room = _room.value!;
    final known = (_players.value ?? const []).any((p) => p.uid == uid);
    String? problem;
    if (room.closed) {
      problem = 'Dieses Dorf wurde verlassen.';
    } else if (!known && room.phase != Phase.lobby) {
      problem = 'Das Spiel in diesem Dorf hat bereits begonnen.';
    } else if (!known && (_players.value ?? const []).length >= maxPlayers) {
      problem = 'Das Dorf ist voll ($maxPlayers Spieler).';
    }
    if (problem != null) {
      await _reset();
      throw RoomException(problem);
    }
    _sendJoin();
    _beat = Timer.periodic(const Duration(seconds: 4), (_) => _sendJoin());
    final ok = await _waitFor(
        () => (_players.value ?? const []).any((p) => p.uid == uid && p.stamp == _stamp), joinTimeout * 2);
    if (!ok) {
      await _reset();
      throw RoomException('Der Spielleiter antwortet nicht. Versuche es erneut.');
    }
  }

  Future<bool> _waitFor(bool Function() test, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (!test()) {
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return true;
  }

  void _sendJoin() => _sendSealed('$_ch/join/$uid', _roomKey, {'name': _name, 'stamp': _stamp, 'pub': _myPub});

  /// Verschlüsselt und sendet in der Reihenfolge der Aufrufe.
  void _sendSealed(String topic, SecretKey? key, Object json, {bool retain = false}) {
    if (key == null) return;
    final sealed = Crypto.seal(key, json);
    _out = _out.then((_) async {
      final payload = await sealed;
      _t?.publish(topic, payload, retain: retain);
    }).catchError((Object e) => debugPrint('Senden: $e'));
  }

  // ------------------------------------------------------------------
  // Spielleiter
  // ------------------------------------------------------------------

  void _hostFlush(Set<String> changedSecrets) {
    final store = hostStore;
    if (store == null) return;
    final state = {'room': store.room, 'players': store.players, 'hostPub': _myPub, 'now': _now};
    _sendSealed('$_ch/state', _roomKey, state, retain: true);
    _emitState(state, 0);
    for (final u in changedSecrets) {
      _publishSecret(u);
    }
  }

  void _publishSecret(String u) {
    final store = hostStore;
    if (store == null) return;
    final data = store.secrets[u] ?? const <String, dynamic>{};
    if (u == uid) {
      _secret.add(SecretState(Map<String, dynamic>.from(data)));
      return;
    }
    final pub = _pubs[u];
    if (pub == null) return;
    final topic = '$_ch/secret/$u';
    // Jetzt einfrieren: gesendet wird erst später, der Zustand ändert sich weiter.
    final frozenJson = _deepCopy(data);
    _out = _out.then((_) async {
      final key = await _sharedWith(u, pub);
      final payload = await Crypto.seal(key, {'s': frozenJson});
      _t?.publish(topic, payload, retain: true);
    }).catchError((Object e) => debugPrint('Senden: $e'));
  }

  static dynamic _deepCopy(dynamic v) {
    if (v is Map) return {for (final e in v.entries) e.key as String: _deepCopy(e.value)};
    if (v is List) return [for (final e in v) _deepCopy(e)];
    return v;
  }

  Future<SecretKey> _sharedWith(String u, String pub) async =>
      _shared['$u|$pub'] ??= await Crypto.shared(_pair!, pub);

  void _pruneLobby() {
    final store = hostStore;
    if (store == null || store.room['phase'] != Phase.lobby) return;
    for (final u in store.players.keys.toList()) {
      if (u == uid) continue;
      if (_now - (_lastSeen[u] ?? 0) > 15000) store.removePlayer(u);
    }
  }

  void _onReconnected() {
    final store = hostStore;
    if (store != null) {
      _hostFlush(store.secrets.keys.toSet());
    } else if (_code != null) {
      _sendJoin();
    }
  }

  // ------------------------------------------------------------------
  // Eingehende Nachrichten
  // ------------------------------------------------------------------

  Future<void> _handle(NetMessage m) async {
    if (_ch.isEmpty || !m.topic.startsWith('$_ch/')) return;
    final parts = m.topic.substring(_ch.length + 1).split('/');
    final kind = parts[0];
    final who = parts.length > 1 ? parts[1] : '';
    final store = hostStore;

    if (kind == 'signal') {
      final s = await Crypto.open(_roomKey!, m.payload);
      if (s != null && !_signals.isClosed) _signals.add(s);
      return;
    }

    if (store == null) {
      if (kind == 'state') {
        final s = await Crypto.open(_roomKey!, m.payload);
        if (s == null) return;
        final hp = s['hostPub'] as String?;
        if (hp != null && hp != _hostPub) {
          _hostPub = hp;
          _hostShared = await Crypto.shared(_pair!, hp);
          await _openSecret();
        }
        _emitState(s, _now - ((s['now'] as num?)?.toInt() ?? _now));
      } else if (kind == 'secret') {
        _rawSecret = m.payload;
        await _openSecret();
      }
      return;
    }

    switch (kind) {
      case 'join':
        final j = await Crypto.open(_roomKey!, m.payload);
        final pub = j?['pub'], stamp = j?['stamp'], name = j?['name'];
        if (j == null || pub is! String || stamp is! String || name is! String || who.isEmpty || who == uid) return;
        _lastSeen[who] = _now;
        final existing = store.players[who];
        if (existing != null) {
          if (_pubs[who] != pub) {
            _pubs[who] = pub;
            store.touchSecret(who);
          }
          if (existing['stamp'] != stamp) store.updatePlayer(who, {'stamp': stamp});
        } else if (store.room['phase'] == Phase.lobby && store.players.length < maxPlayers) {
          _pubs[who] = pub;
          final clean = name.trim();
          store.setPlayer(who, _newPlayer(clean.length > 16 ? clean.substring(0, 16) : clean, stamp));
        }
      case 'leave':
        final j = await Crypto.open(_roomKey!, m.payload);
        if (j != null && who != uid && store.room['phase'] == Phase.lobby) store.removePlayer(who);
      case 'action':
        final pub = _pubs[who];
        if (pub == null) return;
        final a = await Crypto.open(await _sharedWith(who, pub), m.payload);
        if (a != null) store.putAction(who, a);
    }
  }

  Future<void> _openSecret() async {
    final raw = _rawSecret, key = _hostShared;
    if (raw == null || key == null) return;
    final s = await Crypto.open(key, raw);
    if (s != null) _secret.add(SecretState(Map<String, dynamic>.from(s['s'] as Map? ?? const {})));
  }

  void _emitState(Map<String, dynamic> s, int clockOffset) {
    final code = _code;
    if (code == null) return;
    final room = Map<String, dynamic>.from(_deepCopy(s['room'] ?? const {}) as Map);
    final ends = room['endsAt'];
    if (ends is num) room['endsAt'] = ends.toInt() + clockOffset;
    final players = [
      for (final e in (s['players'] as Map? ?? const {}).entries)
        PlayerState(e.key as String, Map<String, dynamic>.from(_deepCopy(e.value) as Map)),
    ]..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    _players.add(players);
    _room.add(RoomState(code, room));
  }

  // ------------------------------------------------------------------
  // Öffentliche Schnittstelle für die Oberfläche
  // ------------------------------------------------------------------

  Stream<RoomState?> watchRoom(String code) => _room.stream;
  Stream<List<PlayerState>> watchPlayers(String code) => _players.stream;
  Stream<SecretState> watchSecret(String code) => _secret.stream;
  Stream<Map<String, dynamic>?> watchMyAction(String code) => _myAction.stream;

  /// WebRTC-Signale anderer Spieler an mich.
  Stream<Map<String, dynamic>> get signals => _signals.stream;

  Future<void> sendSignal(String to, Map<String, dynamic> data) async =>
      _sendSealed('$_ch/signal/$to', _roomKey, {...data, 'from': uid, 'to': to});

  Future<void> updateSettings(String code, Map<String, int> roles, bool mayor, int day) async =>
      hostStore?.updateRoom({
        'settings': {'roles': roles, 'mayor': mayor, 'day': day},
      });

  /// Schreibt die Aktion des Spielers für die aktuelle Phase.
  Future<void> submitAction(String code, String key, Map<String, dynamic> data) async {
    final a = {...data, 'key': key, 'ts': _now};
    _myAction.add(a);
    final store = hostStore;
    if (store != null) {
      store.putAction(uid, a);
    } else {
      _sendSealed('$_ch/action/$uid', _hostShared, a, retain: true);
    }
  }

  Future<void> leaveRoom(String code, {required bool isHost, required bool inLobby}) async {
    final current = _t;
    if (current == null) return;
    try {
      final store = hostStore;
      if (store != null) {
        store.updateRoom({'closed': true});
      } else if (inLobby) {
        _sendSealed('$_ch/leave/$uid', _roomKey, {'bye': true});
      }
      await Future<void>.delayed(Duration.zero);
      await _out;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } catch (_) {}
    // Inzwischen ein neues Dorf betreten? Dann nichts mehr abbauen.
    if (identical(_t, current)) await _reset();
  }

  Future<void> _reset() async {
    _beat?.cancel();
    _beat = null;
    await _msgSub?.cancel();
    await _reSub?.cancel();
    final t = _t;
    _t = null;
    try {
      await t?.disconnect();
    } catch (_) {}
    hostStore?.dispose();
    hostStore = null;
    _code = null;
    _ch = '';
    _roomKey = null;
    _pubs.clear();
    _shared.clear();
    _lastSeen.clear();
    _hostPub = null;
    _hostShared = null;
    _rawSecret = null;
    _out = Future.value();
    _room.close();
    _players.close();
    _secret.close();
    _myAction.close();
    await _signals.close();
    _room = _Latest();
    _players = _Latest();
    _secret = _Latest();
    _myAction = _Latest();
    _signals = StreamController.broadcast();
  }
}
