import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/game_state.dart';
import '../models/roles.dart';

class _Pending {
  _Pending(this.type, this.uid);
  final String type; // Phase.hunter | Phase.successor
  final String uid;
}

/// Der Spielleiter. Läuft ausschließlich auf dem Gerät des Gastgebers und ist
/// die einzige Instanz, die Rollen kennt und den Spielablauf in Firestore schreibt.
class GameEngine {
  GameEngine(this.code, {FirebaseFirestore? db, this.timeScale = 1.0, Random? random})
      : _db = db ?? FirebaseFirestore.instance,
        _rnd = random ?? Random();

  final String code;
  final FirebaseFirestore _db;
  final Random _rnd;

  /// Nur für Tests: verkürzt alle Wartezeiten.
  final double timeScale;

  DocumentReference<Map<String, dynamic>> get _room => _db.collection('rooms').doc(code);
  DocumentReference<Map<String, dynamic>> _secret(String uid) =>
      _room.collection('secrets').doc(uid);
  DocumentReference<Map<String, dynamic>> _player(String uid) =>
      _room.collection('players').doc(uid);

  // ---- Spielzustand (nur im Speicher des Gastgebers) ----
  final Map<String, Role> _roles = {};
  final Map<String, String> _names = {};
  final Set<String> _alive = {};
  final Set<String> _silenced = {}; // enttarnte Dorfdeppen
  final List<_Pending> _pending = [];
  Map<String, int> _roleCounts = {};
  bool _mayorEnabled = true;
  int _dayDuration = 180;
  String? _mayor;
  String? _lover1, _lover2;
  bool _healUsed = false, _poisonUsed = false, _elderLifeUsed = false;
  String? _protectedLast;
  int _round = 0;
  int _narrationId = 0;

  // ---- Laufzeit ----
  Map<String, Map<String, dynamic>> _actions = {};
  StreamSubscription? _sub;
  Completer<void>? _wake;
  bool _skip = false;
  bool _disposed = false;
  String _phase = Phase.lobby;
  NightStep? _step;
  String _key = '';
  String _lastPackJson = '';
  String _lastTallyJson = '';

  Future<void> _done = Future.value();

  /// Abgeschlossen, sobald das Spiel endet (für Tests).
  Future<void> get done => _done;

  bool get running => !_disposed && _phase != Phase.lobby && _phase != Phase.end;
  String get phase => _phase;

  /// Überspringt den laufenden Countdown (z.B. Diskussion vorzeitig beenden).
  void skip() {
    _skip = true;
    _poke();
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _poke();
  }

  // =====================================================================
  // Start
  // =====================================================================

  Future<void> start(List<PlayerState> players, RoomState room) async {
    _roleCounts = room.roleCounts;
    _mayorEnabled = room.mayorEnabled;
    _dayDuration = room.dayDuration;

    final deck = <Role>[
      for (final e in _roleCounts.entries)
        for (var i = 0; i < e.value; i++) Role.fromId(e.key) ?? Role.dorfbewohner,
    ]..shuffle(_rnd);
    if (deck.length != players.length) {
      throw StateError('Anzahl der Rollen passt nicht zur Spielerzahl.');
    }
    final shuffled = [...players]..shuffle(_rnd);
    for (var i = 0; i < shuffled.length; i++) {
      final p = shuffled[i];
      _roles[p.uid] = deck[i];
      _names[p.uid] = p.name;
      _alive.add(p.uid);
    }

    await _clearCollection('actions');
    await _clearCollection('secrets');

    final wolves = _roles.entries.where((e) => e.value.isWolf).map((e) => e.key).toList();
    final batch = _db.batch();
    for (final uid in _roles.keys) {
      batch.set(_secret(uid), {
        'role': _roles[uid]!.id,
        if (_roles[uid]!.isWolf) 'wolves': wolves,
        'expiresAt': _expires,
      });
      batch.update(_player(uid), {
        'alive': true,
        'role': FieldValue.delete(),
        'mayor': false,
        'canVote': true,
        'lover': false,
      });
    }
    await batch.commit();

    _sub = _room.collection('actions').snapshots().listen((q) {
      _actions = {for (final d in q.docs) d.id: d.data()};
      _onActionsChanged();
      _poke();
    });

    _done = _loop();
    unawaited(_done);
  }

  Timestamp get _expires =>
      Timestamp.fromMillisecondsSinceEpoch(DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch);

  Future<void> _clearCollection(String name) async {
    final q = await _room.collection(name).get();
    final batch = _db.batch();
    for (final d in q.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  /// Setzt den Raum nach Spielende zurück in die Lobby.
  static Future<void> resetToLobby(String code, {FirebaseFirestore? firestore}) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final room = db.collection('rooms').doc(code);
    final batch = db.batch();
    for (final c in ['actions', 'secrets']) {
      final q = await room.collection(c).get();
      for (final d in q.docs) {
        batch.delete(d.reference);
      }
    }
    final players = await room.collection('players').get();
    for (final d in players.docs) {
      batch.update(d.reference, {
        'alive': true,
        'role': FieldValue.delete(),
        'mayor': false,
        'canVote': true,
        'lover': false,
      });
    }
    batch.update(room, {
      'phase': Phase.lobby,
      'step': null,
      'round': 0,
      'endsAt': null,
      'narration': '',
      'actionKey': '',
      'actor': null,
      'winner': null,
      'winners': [],
      'tally': {},
    });
    await batch.commit();
  }

  // =====================================================================
  // Hauptschleife
  // =====================================================================

  Future<void> _loop() async {
    try {
      while (!_disposed) {
        _round++;
        await _night();
        if (_disposed || await _checkWin()) return;
        if (_round == 1 && _mayorEnabled && _mayor == null) {
          await _mayorElection();
          if (_disposed) return;
        }
        await _day();
        if (_disposed || await _checkWin()) return;
      }
    } catch (e, st) {
      debugPrint('GameEngine-Fehler: $e\n$st');
    }
  }

  // ---------------------------------------------------------------- Nacht

  bool _inGame(Role r) => (_roleCounts[r.id] ?? 0) > 0;
  List<String> _aliveWith(bool Function(Role r) test) =>
      _alive.where((u) => test(_roles[u]!)).toList();

  bool _stepActive(NightStep s) => switch (s) {
        NightStep.amor => _round == 1 && _inGame(Role.amor),
        NightStep.beschuetzer => _inGame(Role.beschuetzer),
        NightStep.seherin => _inGame(Role.seherin),
        NightStep.werwoelfe => true,
        NightStep.weisserWerwolf => _round.isEven && _inGame(Role.weisserWerwolf),
        NightStep.hexe => _inGame(Role.hexe),
      };

  List<String> _actorsFor(NightStep s) => switch (s) {
        NightStep.amor => _aliveWith((r) => r == Role.amor),
        NightStep.beschuetzer => _aliveWith((r) => r == Role.beschuetzer),
        NightStep.seherin => _aliveWith((r) => r == Role.seherin),
        NightStep.werwoelfe => _aliveWith((r) => r.isWolf),
        NightStep.weisserWerwolf =>
          _aliveWith((r) => r == Role.weisserWerwolf),
        NightStep.hexe =>
          (_healUsed && _poisonUsed) ? <String>[] : _aliveWith((r) => r == Role.hexe),
      };

  int _stepSeconds(NightStep s) => switch (s) {
        NightStep.werwoelfe => 60,
        NightStep.hexe => 45,
        _ => 35,
      };

  Map<String, Map<String, dynamic>> _current() => {
        for (final e in _actions.entries)
          if (e.value['key'] == _key) e.key: e.value,
      };

  bool _validAlive(Object? uid) => uid is String && _alive.contains(uid);

  Future<void> _night() async {
    await _setPhase(
      Phase.night,
      narration: _round == 1
          ? 'Die Nacht senkt sich über das Dorf. Prägt euch eure Rolle ein … dann schließt die Augen.'
          : 'Die Nacht kehrt zurück. Schließt die Augen. Irgendwo im Wald knackt ein Ast.',
      seconds: _round == 1 ? 15 : 8,
    );
    await _wait(_round == 1 ? 15 : 8);

    String? wolfTarget, whiteTarget, poisonTarget, protectedNow;
    var healed = false;

    for (final step in NightStep.values) {
      if (_disposed) return;
      if (!_stepActive(step)) continue;
      final actors = _actorsFor(step);
      final key = 'r$_round-${step.id}';

      if (step == NightStep.werwoelfe) await _prepareWolfNight();
      if (step == NightStep.hexe) {
        for (final w in _aliveWith((r) => r == Role.hexe)) {
          await _secret(w).set({
            'witch': {'victim': wolfTarget, 'healUsed': _healUsed, 'poisonUsed': _poisonUsed},
          }, SetOptions(merge: true));
        }
      }

      final seconds = _stepSeconds(step);
      await _setPhase(Phase.night, step: step, narration: step.narration, seconds: seconds, key: key);

      if (actors.isEmpty) {
        // Rolle tot oder verbraucht: trotzdem warten, damit niemand etwas ableiten kann.
        await _wait(7 + _rnd.nextInt(6));
        continue;
      }
      await _waitFor(seconds, () {
        final cur = _current();
        return actors.every((a) => cur.containsKey(a));
      });
      final cur = _current();

      switch (step) {
        case NightStep.amor:
          final a = cur[actors.first];
          var l1 = a?['target'], l2 = a?['target2'];
          if (!_validAlive(l1) || !_validAlive(l2) || l1 == l2) {
            final pool = _alive.toList()..shuffle(_rnd);
            l1 = pool[0];
            l2 = pool[1];
          }
          _lover1 = l1 as String;
          _lover2 = l2 as String;
          await _secret(_lover1!).set({'lover': _lover2}, SetOptions(merge: true));
          await _secret(_lover2!).set({'lover': _lover1}, SetOptions(merge: true));
        case NightStep.beschuetzer:
          final t = cur[actors.first]?['target'];
          protectedNow = (_validAlive(t) && t != _protectedLast) ? t as String : null;
          _protectedLast = protectedNow;
          await _secret(actors.first).set({'protectedLast': protectedNow}, SetOptions(merge: true));
        case NightStep.seherin:
          final t = cur[actors.first]?['target'];
          if (_validAlive(t)) {
            await _secret(actors.first).set({
              'seen': {t as String: _roles[t]!.id},
            }, SetOptions(merge: true));
            await _wait(5); // Zeit, die Vision zu lesen
          }
        case NightStep.werwoelfe:
          wolfTarget = _majority(
            {for (final a in actors) a: cur[a]?['target']},
            (t) => _validAlive(t) && !_roles[t]!.isWolf,
          );
          await _wait(3);
        case NightStep.weisserWerwolf:
          final t = cur[actors.first]?['target'];
          if (_validAlive(t) && _roles[t]!.isWolf && t != actors.first) whiteTarget = t as String;
        case NightStep.hexe:
          final a = cur[actors.first];
          if (a?['heal'] == true && !_healUsed && wolfTarget != null) {
            healed = true;
            _healUsed = true;
          }
          final p = a?['poison'];
          if (!_poisonUsed && _validAlive(p)) {
            poisonTarget = p as String;
            _poisonUsed = true;
          }
          await _secret(actors.first).set({
            'witch': {'victim': null, 'healUsed': _healUsed, 'poisonUsed': _poisonUsed},
          }, SetOptions(merge: true));
      }
    }
    if (_disposed) return;

    // ---- Auflösung der Nacht ----
    final victims = <String>{};
    if (wolfTarget != null && wolfTarget != protectedNow && !healed) {
      if (_roles[wolfTarget] == Role.dorfaeltester && !_elderLifeUsed) {
        _elderLifeUsed = true;
      } else {
        victims.add(wolfTarget);
      }
    }
    if (whiteTarget != null) victims.add(whiteTarget);
    if (poisonTarget != null) victims.add(poisonTarget);

    final dead = await _kill(victims);
    final String text;
    if (dead.isEmpty) {
      text = 'Der Morgen graut. Das Dorf erwacht … und alle Augen öffnen sich. Niemand ist in dieser Nacht gestorben.';
    } else {
      final lines = dead.map((d) => d.$2
          ? '${_names[d.$1]} folgt der geliebten Seele in den Tod – ${_roles[d.$1]!.name}.'
          : '${_names[d.$1]} wurde tot aufgefunden – ${_roles[d.$1]!.name}.');
      text = 'Der Morgen graut. Das Dorf erwacht, doch nicht alle öffnen die Augen. ${lines.join(' ')}';
    }
    await _setPhase(Phase.dawn, narration: text, seconds: 12);
    await _wait(12);
    await _processPending();
  }

  Future<void> _prepareWolfNight() async {
    final wolves = _aliveWith((r) => r.isWolf);
    final girls = _aliveWith((r) => r == Role.maedchen);
    final ghosts = _roles.keys.where((u) => !_alive.contains(u));
    final audience = <String, String>{
      for (final w in wolves) w: 'full',
      for (final g in girls) g: 'video',
      for (final g in ghosts) g: 'video',
    };
    _lastPackJson = '';
    final batch = _db.batch();
    for (final w in wolves) {
      batch.set(_secret(w), {'audience': audience, 'pack': {}, 'wolves': wolves}, SetOptions(merge: true));
    }
    for (final g in girls) {
      batch.set(_secret(g), {'peek': [...wolves]..shuffle(_rnd)}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Mehrheitsentscheid. Gleichstand → Zufall unter den Führenden.
  String? _majority(Map<String, Object?> votes, bool Function(String) valid,
      {Map<String, int> weights = const {}, bool tieMeansNone = false}) {
    final count = <String, int>{};
    votes.forEach((voter, t) {
      if (t is String && valid(t)) count[t] = (count[t] ?? 0) + (weights[voter] ?? 1);
    });
    if (count.isEmpty) return null;
    final best = count.values.reduce(max);
    final top = count.entries.where((e) => e.value == best).map((e) => e.key).toList();
    if (top.length > 1 && tieMeansNone) return null;
    return top[_rnd.nextInt(top.length)];
  }

  // ---------------------------------------------------------------- Tod

  /// Tötet die Spieler und alle, die ihnen folgen (Verliebte).
  /// Liefert (uid, ausKummer) in Reihenfolge.
  Future<List<(String, bool)>> _kill(Set<String> uids) async {
    final result = <(String, bool)>[];
    final queue = [...uids.where(_alive.contains)];
    final grief = <String>{};
    while (queue.isNotEmpty) {
      final u = queue.removeAt(0);
      if (!_alive.remove(u)) continue;
      result.add((u, grief.contains(u)));
      final partner = u == _lover1 ? _lover2 : (u == _lover2 ? _lover1 : null);
      if (partner != null && _alive.contains(partner) && !queue.contains(partner)) {
        grief.add(partner);
        queue.add(partner);
      }
    }
    if (result.isEmpty) return result;

    final batch = _db.batch();
    final allRoles = {for (final e in _roles.entries) e.key: e.value.id};
    for (final (u, _) in result) {
      batch.update(_player(u), {'alive': false, 'role': _roles[u]!.id, 'mayor': false});
      batch.set(_secret(u), {'ghost': true, 'allRoles': allRoles}, SetOptions(merge: true));
      if (_roles[u] == Role.jaeger) _pending.add(_Pending(Phase.hunter, u));
      if (_mayor == u) {
        _mayor = null;
        _pending.add(_Pending(Phase.successor, u));
      }
    }
    await batch.commit();
    return result;
  }

  Future<void> _processPending() async {
    while (_pending.isNotEmpty && !_disposed) {
      final p = _pending.removeAt(0);
      if (_alive.isEmpty) return;
      if (p.type == Phase.hunter) {
        final key = 'r$_round-hunter-${p.uid}';
        await _setPhase(Phase.hunter,
            narration:
                '${_names[p.uid]} war der Jäger. Mit dem letzten Atemzug hebt er die Flinte …',
            seconds: 30,
            key: key,
            actor: p.uid);
        await _waitFor(30, () => _current().containsKey(p.uid));
        final t = _current()[p.uid]?['target'];
        if (_validAlive(t) && t != p.uid) {
          final dead = await _kill({t as String});
          final lines = dead.map((d) => d.$2
              ? '${_names[d.$1]} folgt der geliebten Seele in den Tod – ${_roles[d.$1]!.name}.'
              : 'Ein Schuss hallt durch den Nebel. ${_names[d.$1]} fällt – ${_roles[d.$1]!.name}.');
          await _setPhase(Phase.dawn, narration: lines.join(' '), seconds: 8);
        } else {
          await _setPhase(Phase.dawn,
              narration: 'Die Hand des Jägers zittert. Der Schuss verfehlt sein Ziel.', seconds: 6);
        }
        await _wait(8);
      } else {
        final key = 'r$_round-successor';
        await _setPhase(Phase.successor,
            narration:
                'Der Bürgermeister ist tot. Mit letzter Kraft bestimmt er, wer sein Amt erbt.',
            seconds: 30,
            key: key,
            actor: p.uid);
        await _waitFor(30, () => _current().containsKey(p.uid));
        var t = _current()[p.uid]?['target'];
        if (!_validAlive(t)) t = (_alive.toList()..shuffle(_rnd)).first;
        await _setMayor(t as String);
        await _setPhase(Phase.dawn,
            narration: '${_names[t]} trägt nun die Amtskette des Bürgermeisters.', seconds: 6);
        await _wait(6);
      }
    }
  }

  Future<void> _setMayor(String uid) async {
    _mayor = uid;
    await _player(uid).update({'mayor': true});
  }

  // ---------------------------------------------------------------- Tag

  Future<void> _mayorElection() async {
    final key = 'r$_round-mayor';
    await _setPhase(Phase.mayorElection,
        narration:
            'Das Dorf braucht eine Stimme, die schwerer wiegt. Wählt euren Bürgermeister.',
        seconds: 90,
        key: key);
    await _waitFor(90, () => _alive.every(_current().containsKey));
    final cur = _current();
    var winner = _majority({for (final u in _alive) u: cur[u]?['target']}, _validAlive);
    winner ??= (_alive.toList()..shuffle(_rnd)).first;
    await _setMayor(winner);
    await _setPhase(Phase.dawn,
        narration:
            '${_names[winner]} ist Bürgermeister. Bei jedem Urteil zählt diese Stimme doppelt.',
        seconds: 7,
        keepTally: true);
    await _wait(7);
  }

  Future<void> _day() async {
    await _setPhase(Phase.day,
        narration:
            'Wer von euch trägt das Fell der Bestie unter der Haut? Seht einander in die Augen und beratet euch.',
        seconds: _dayDuration);
    await _wait(_dayDuration);
    if (_disposed) return;

    final key = 'r$_round-vote';
    final voters = _alive.where((u) => !_silenced.contains(u)).toList();
    await _setPhase(Phase.vote,
        narration: 'Die Zeit des Redens ist vorbei. Zeigt mit dem Finger auf den Schuldigen.',
        seconds: 60,
        key: key);
    await _waitFor(60, () => voters.every(_current().containsKey));
    final cur = _current();
    final victim = _majority(
      {for (final u in voters) u: cur[u]?['target']},
      _validAlive,
      weights: {?_mayor: 2},
      tieMeansNone: true,
    );

    if (victim == null) {
      await _setPhase(Phase.dawn,
          narration: 'Das Dorf ist uneins. Heute wird niemand gerichtet – und die Nacht naht.',
          seconds: 8,
          keepTally: true);
      await _wait(8);
      return;
    }
    if (_roles[victim] == Role.dorfdepp && !_silenced.contains(victim)) {
      _silenced.add(victim);
      await _player(victim).update({'role': Role.dorfdepp.id, 'canVote': false});
      await _setPhase(Phase.dawn,
          narration:
              'Als der Strick sich spannt, erkennt das Dorf ${_names[victim]}: den Dorfdepp. Man lässt ihn laufen – doch seine Stimme zählt nicht mehr.',
          seconds: 10,
          keepTally: true);
      await _wait(10);
      return;
    }
    final dead = await _kill({victim});
    final lines = dead.map((d) => d.$2
        ? '${_names[d.$1]} folgt der geliebten Seele in den Tod – ${_roles[d.$1]!.name}.'
        : 'Das Dorf hat gerichtet. ${_names[d.$1]} wird gehängt – ${_roles[d.$1]!.name}.');
    await _setPhase(Phase.dawn, narration: lines.join(' '), seconds: 10, keepTally: true);
    await _wait(10);
    await _processPending();
  }

  // ---------------------------------------------------------------- Sieg

  String? _winner() {
    final al = _alive.toList();
    if (al.isEmpty) return Winner.none;
    if (_lover1 != null &&
        al.length == 2 &&
        al.contains(_lover1) &&
        al.contains(_lover2) &&
        _roles[_lover1]!.isWolf != _roles[_lover2]!.isWolf) {
      return Winner.lovers;
    }
    final wolves = al.where((u) => _roles[u]!.isWolf).toList();
    if (wolves.isEmpty) return Winner.village;
    if (al.length == 1 && _roles[al.first] == Role.weisserWerwolf) return Winner.white;
    if (wolves.length == al.length && !al.any((u) => _roles[u] == Role.weisserWerwolf)) {
      return Winner.wolves;
    }
    return null;
  }

  Future<bool> _checkWin() async {
    final w = _winner();
    if (w == null) return false;
    final winners = switch (w) {
      Winner.village => _roles.keys.where((u) => _roles[u]!.team == Team.village).toList(),
      Winner.wolves => _roles.keys.where((u) => _roles[u] == Role.werwolf).toList(),
      Winner.white => _roles.keys.where((u) => _roles[u] == Role.weisserWerwolf).toList(),
      Winner.lovers => [_lover1!, _lover2!],
      _ => <String>[],
    };
    final batch = _db.batch();
    for (final u in _roles.keys) {
      batch.update(_player(u), {
        'role': _roles[u]!.id,
        'lover': u == _lover1 || u == _lover2,
      });
    }
    await batch.commit();
    _phase = Phase.end;
    await _room.update({
      'phase': Phase.end,
      'step': null,
      'endsAt': null,
      'winner': w,
      'winners': winners,
      'narration': Winner.narration(w),
      'narrationId': ++_narrationId,
      'actionKey': '',
      'actor': null,
    });
    _sub?.cancel();
    return true;
  }

  // ---------------------------------------------------------------- Hilfen

  Future<void> _setPhase(String phase,
      {NightStep? step,
      required String narration,
      required int seconds,
      String key = '',
      String? actor,
      bool keepTally = false}) async {
    _phase = phase;
    _step = step;
    _key = key;
    _lastTallyJson = '';
    await _room.update({
      'phase': phase,
      'step': step?.id,
      'round': _round,
      'endsAt': DateTime.now().millisecondsSinceEpoch + seconds * 1000,
      'narration': narration,
      'narrationId': ++_narrationId,
      'actionKey': key,
      'actor': actor,
      if (!keepTally) 'tally': {},
    });
  }

  void _onActionsChanged() {
    final cur = _current();
    // Live-Stimmen des Rudels an alle Wölfe.
    if (_phase == Phase.night && _step == NightStep.werwoelfe) {
      final pack = <String, String>{
        for (final e in cur.entries)
          if (e.value['target'] is String) e.key: e.value['target'] as String,
      };
      final json = jsonEncode(pack);
      if (json != _lastPackJson) {
        _lastPackJson = json;
        for (final w in _aliveWith((r) => r.isWolf)) {
          _secret(w).set({'pack': pack}, SetOptions(merge: true));
        }
      }
    }
    // Offene Abstimmung am Tag.
    if (_phase == Phase.vote || _phase == Phase.mayorElection) {
      final tally = <String, int>{};
      for (final e in cur.entries) {
        final t = e.value['target'];
        if (!_alive.contains(e.key) || !_validAlive(t)) continue;
        if (_phase == Phase.vote && _silenced.contains(e.key)) continue;
        final w = (_phase == Phase.vote && e.key == _mayor) ? 2 : 1;
        tally[t as String] = (tally[t] ?? 0) + w;
      }
      final json = jsonEncode(tally);
      if (json != _lastTallyJson) {
        _lastTallyJson = json;
        _room.update({'tally': tally});
      }
    }
  }

  void _poke() {
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _wait(int seconds) => _waitFor(seconds, null);

  Future<void> _waitFor(int seconds, bool Function()? done) async {
    final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000 * timeScale).round()));
    _skip = false;
    while (!_disposed && !_skip) {
      if (done != null && done()) return;
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero) return;
      final wake = _wake = Completer<void>();
      await Future.any([wake.future, Future<void>.delayed(remaining)]);
    }
  }
}
