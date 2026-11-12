import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:werwolf/models/game_state.dart';
import 'package:werwolf/models/roles.dart';
import 'package:werwolf/net/host_store.dart';
import 'package:werwolf/services/game_engine.dart';

/// Simuliert komplette Partien mit Bot-Spielern direkt auf dem Spielzustand.
Future<({RoomState room, List<PlayerState> players, Set<String> phases})> playGame(
  int seed,
  Map<String, int> roles, {
  bool mayor = true,
}) async {
  final rnd = Random(seed);
  const code = 'TEST1';
  final n = roles.values.fold<int>(0, (a, b) => a + b);
  final uids = [for (var i = 0; i < n; i++) 'p$i'];
  final phases = <String>{};
  var lastKey = '';
  late final HostStore store;

  List<PlayerState> playerStates() =>
      [for (final e in store.players.entries) PlayerState(e.key, Map<String, dynamic>.from(e.value))];

  void bots() {
    final r = RoomState(code, Map<String, dynamic>.from(store.room));
    phases.add(r.step != null ? '${r.phase}:${r.step!.id}' : r.phase);
    if (r.actionKey.isEmpty || r.actionKey == lastKey) return;
    lastKey = r.actionKey;
    final ps = playerStates();
    final alive = ps.where((p) => p.alive).map((p) => p.uid).toList();
    String pick(List<String> from) => from[rnd.nextInt(from.length)];
    void act(String uid, Map<String, dynamic> data) => store.putAction(uid, {...data, 'key': r.actionKey});

    for (final uid in uids) {
      final sec = SecretState(Map<String, dynamic>.from(store.secrets[uid] ?? const {}));
      final me = ps.firstWhere((p) => p.uid == uid);
      final others = alive.where((u) => u != uid).toList();
      if (r.phase == Phase.night && me.alive) {
        switch (r.step) {
          case NightStep.amor when sec.role == Role.amor:
            final two = ([...alive]..shuffle(rnd)).take(2).toList();
            act(uid, {'target': two[0], 'target2': two[1]});
          case NightStep.beschuetzer when sec.role == Role.beschuetzer:
            final c = alive.where((u) => u != sec.protectedLast).toList();
            if (c.isNotEmpty) act(uid, {'target': pick(c)});
          case NightStep.seherin when sec.role == Role.seherin:
            if (others.isNotEmpty) act(uid, {'target': pick(others)});
          case NightStep.werwoelfe when sec.role?.isWolf ?? false:
            final prey = alive.where((u) => !sec.wolves.contains(u)).toList();
            if (prey.isNotEmpty) act(uid, {'target': pick(prey)});
          case NightStep.weisserWerwolf when sec.role == Role.weisserWerwolf:
            final bro = sec.wolves.where((w) => w != uid && alive.contains(w)).toList();
            act(uid, {'target': bro.isEmpty ? null : pick(bro)});
          case NightStep.hexe when sec.role == Role.hexe:
            act(uid, {
              'heal': rnd.nextBool(),
              'poison': rnd.nextInt(3) == 0 && others.isNotEmpty ? pick(others) : null,
              'done': true,
            });
          default:
        }
      } else if ((r.phase == Phase.vote && me.alive && me.canVote) ||
          (r.phase == Phase.mayorElection && me.alive)) {
        if (others.isNotEmpty) act(uid, {'target': pick(others)});
      } else if ((r.phase == Phase.hunter || r.phase == Phase.successor) && r.actor == uid) {
        if (others.isNotEmpty) act(uid, {'target': pick(others)});
      }
    }
  }

  store = HostStore(hostId: uids.first, onFlush: (_) => bots());
  store.updateRoom({
    'settings': {'roles': roles, 'mayor': mayor, 'day': 60},
  });
  for (var i = 0; i < n; i++) {
    store.setPlayer(uids[i], {
      'name': 'Spieler$i',
      'stamp': 's$i',
      'joinedAt': i,
      'alive': true,
      'mayor': false,
      'canVote': true,
    });
  }

  final engine = GameEngine(store, timeScale: 0.002, random: Random(seed));
  await engine.start(playerStates(), RoomState(code, Map<String, dynamic>.from(store.room)));
  await engine.done.timeout(const Duration(seconds: 60));
  await Future<void>.delayed(const Duration(milliseconds: 5));
  engine.dispose();

  final res = (
    room: RoomState(code, Map<String, dynamic>.from(store.room)),
    players: playerStates(),
    phases: phases,
  );
  store.dispose();
  return res;
}

void main() {
  test('Standardverteilungen spielen sich bis zum Ende', () async {
    for (var n = 5; n <= 12; n++) {
      for (var seed = 0; seed < 4; seed++) {
        final res = await playGame(seed * 100 + n, Role.defaultsFor(n));
        expect(res.room.phase, Phase.end, reason: 'n=$n seed=$seed');
        expect(res.room.winner, isNotNull);
        _checkWinner(res.room, res.players);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('Alle Sonderrollen gleichzeitig', () async {
    final roles = {
      Role.werwolf.id: 2,
      Role.weisserWerwolf.id: 1,
      Role.seherin.id: 1,
      Role.hexe.id: 1,
      Role.jaeger.id: 1,
      Role.amor.id: 1,
      Role.beschuetzer.id: 1,
      Role.maedchen.id: 1,
      Role.dorfaeltester.id: 1,
      Role.dorfdepp.id: 1,
      Role.dorfbewohner.id: 1,
    };
    final seen = <String>{};
    final winners = <String>{};
    for (var seed = 0; seed < 25; seed++) {
      final res = await playGame(seed, roles);
      expect(res.room.phase, Phase.end);
      _checkWinner(res.room, res.players);
      seen.addAll(res.phases);
      winners.add(res.room.winner!);
      expect(res.players.every((p) => p.revealedRole != null), isTrue);
      expect(res.players.where((p) => p.lover).length, 2);
    }
    for (final s in NightStep.values) {
      expect(seen, contains('${Phase.night}:${s.id}'), reason: s.id);
    }
    expect(seen, containsAll([Phase.dawn, Phase.mayorElection, Phase.day, Phase.vote, Phase.end]));
    // ignore: avoid_print
    print('Gesehene Sieger: $winners, Phasen: ${seen.length}');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('Verliebte können gemeinsam gewinnen', () async {
    final winners = <String>{};
    for (var seed = 0; seed < 40 && !winners.contains(Winner.lovers); seed++) {
      final res = await playGame(seed, {Role.werwolf.id: 1, Role.amor.id: 1, Role.dorfbewohner.id: 3},
          mayor: false);
      _checkWinner(res.room, res.players);
      winners.add(res.room.winner!);
    }
    expect(winners, contains(Winner.lovers));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('Empfohlene Verteilung passt immer zur Spielerzahl', () {
    for (var n = 3; n <= 12; n++) {
      final m = Role.defaultsFor(n);
      expect(m.values.fold<int>(0, (a, b) => a + b), n);
      expect(m[Role.werwolf.id]! * 2 < n || n < 5, isTrue);
    }
  });
}

void _checkWinner(RoomState room, List<PlayerState> players) {
  final alive = players.where((p) => p.alive).toList();
  final wolvesAlive = alive.where((p) => p.revealedRole!.isWolf).length;
  switch (room.winner) {
    case Winner.village:
      expect(wolvesAlive, 0);
    case Winner.wolves:
      expect(alive.every((p) => p.revealedRole == Role.werwolf), isTrue);
      expect(alive, isNotEmpty);
    case Winner.white:
      expect(alive.length, 1);
      expect(alive.first.revealedRole, Role.weisserWerwolf);
    case Winner.lovers:
      expect(alive.length, 2);
      expect(alive.every((p) => p.lover), isTrue);
    case Winner.none:
      expect(alive, isEmpty);
  }
  for (final w in room.winners) {
    expect(players.any((p) => p.uid == w), isTrue);
  }
}
