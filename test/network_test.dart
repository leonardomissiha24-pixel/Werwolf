import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:werwolf/config.dart';
import 'package:werwolf/models/game_state.dart';
import 'package:werwolf/models/roles.dart';
import 'package:werwolf/net/crypto.dart';
import 'package:werwolf/net/mqtt_transport.dart';
import 'package:werwolf/net/transport.dart';
import 'package:werwolf/services/game_engine.dart';
import 'package:werwolf/services/room_repository.dart';

/// Ein Bot-Spieler: reagiert wie ein Mensch über die öffentliche Schnittstelle.
class Bot {
  Bot(this.repo, this.rnd);
  final RoomRepository repo;
  final Random rnd;
  RoomState? room;
  List<PlayerState> players = [];
  SecretState secret = SecretState.empty();
  String lastKey = '';
  final subs = <StreamSubscription>[];

  void attach() {
    subs.add(repo.watchPlayers('').listen((p) => players = p));
    subs.add(repo.watchSecret('').listen((s) {
      secret = s;
      _act();
    }));
    subs.add(repo.watchRoom('').listen((r) {
      room = r;
      _act();
    }));
  }

  void _act() {
    final r = room;
    if (r == null || r.actionKey.isEmpty || r.actionKey == lastKey || secret.role == null) return;
    final uid = repo.uid;
    final me = players.where((p) => p.uid == uid).firstOrNull;
    if (me == null) return;
    final alive = players.where((p) => p.alive).map((p) => p.uid).toList();
    final others = alive.where((u) => u != uid).toList();
    String pick(List<String> l) => l[rnd.nextInt(l.length)];
    Map<String, dynamic>? a;
    if (r.phase == Phase.night && me.alive) {
      a = switch (r.step) {
        NightStep.amor when secret.role == Role.amor => {'target': alive[0], 'target2': alive[1]},
        NightStep.beschuetzer when secret.role == Role.beschuetzer => {
            'target': pick(alive.where((u) => u != secret.protectedLast).toList())
          },
        NightStep.seherin when secret.role == Role.seherin => {'target': pick(others)},
        NightStep.werwoelfe when secret.role!.isWolf => {
            'target': pick(alive.where((u) => !secret.wolves.contains(u)).toList())
          },
        NightStep.hexe when secret.role == Role.hexe => {'heal': false, 'poison': null, 'done': true},
        _ => null,
      };
    } else if ((r.phase == Phase.vote && me.alive && me.canVote) || (r.phase == Phase.mayorElection && me.alive)) {
      a = {'target': pick(others)};
    } else if ((r.phase == Phase.hunter || r.phase == Phase.successor) && r.actor == uid && others.isNotEmpty) {
      a = {'target': pick(others)};
    }
    if (a != null) {
      lastKey = r.actionKey;
      repo.submitAction('', r.actionKey, a);
    }
  }

  Future<void> dispose() async {
    for (final s in subs) {
      await s.cancel();
    }
  }
}

/// Spielt eine komplette Partie mit [n] Geräten über den gegebenen Transport.
Future<void> playOverNetwork(List<Transport Function()> factories,
    {int n = 6, double timeScale = 0.01, Duration joinTimeout = const Duration(seconds: 2)}) async {
  final rnd = Random(7);
  final repos = [
    for (var i = 0; i < n; i++)
      RoomRepository(uid: RoomRepository.randomId(), transports: factories, joinTimeout: joinTimeout)
  ];
  final host = repos.first;
  final code = await host.createRoom('Wirt');
  expect(code, hasLength(5));

  // Ein Lauscher, der den Dorfcode kennt, schneidet alles mit.
  final spy = factories.first();
  await spy.connect();
  final ch = (await Crypto.forRoom(code)).channel;
  final roomKey = (await Crypto.forRoom(code)).key;
  final overheard = <NetMessage>[];
  spy.messages.listen(overheard.add);
  for (final k in ['secret', 'action']) {
    spy.subscribe('$ch/$k/+');
  }

  await Future.wait([for (var i = 1; i < n; i++) repos[i].joinRoom(code, 'Gast$i')]);
  final bots = [for (final r in repos) Bot(r, rnd)..attach()];
  await _until(() => bots.every((b) => b.players.length == n), 'alle sehen alle Spieler');

  // Falscher Code → verständliche Fehlermeldung.
  final stranger = RoomRepository(uid: RoomRepository.randomId(), transports: factories, joinTimeout: joinTimeout);
  await expectLater(stranger.joinRoom('ZZZZZ', 'X'), throwsA(isA<RoomException>()));

  // Verbindungsaufbau-Signale kommen beim richtigen Empfänger an.
  final got = repos[2].signals.first;
  await repos[1].sendSignal(repos[2].uid, {'type': 'offer', 'sid': 's1', 'sdp': 'v=0'});
  final sig = await got.timeout(const Duration(seconds: 5));
  expect(sig['from'], repos[1].uid);
  expect(sig['sdp'], 'v=0');

  await host.updateSettings(code, Role.defaultsFor(n), true, 60);
  await _until(() => bots.every((b) => b.room?.roleCounts.isNotEmpty ?? false), 'Einstellungen angekommen');

  final engine = GameEngine(host.hostStore!, timeScale: timeScale, random: Random(3));
  await engine.start(bots.first.players, bots.first.room!);
  await engine.done.timeout(const Duration(minutes: 3));
  await _until(() => bots.every((b) => b.room?.phase == Phase.end), 'alle sehen das Spielende');

  for (final b in bots) {
    expect(b.secret.role, isNotNull, reason: 'jeder kennt seine eigene Rolle');
    expect(b.room!.winner, isNotNull);
    expect(b.players.every((p) => p.revealedRole != null), isTrue);
    if (!b.secret.role!.isWolf) expect(b.secret.wolves, isEmpty, reason: 'nur Wölfe kennen das Rudel');
  }

  // Rollen und Nachtaktionen sind für andere nicht lesbar – auch nicht mit dem Dorfcode.
  expect(overheard.where((m) => m.topic.contains('/secret/')), isNotEmpty);
  expect(overheard.where((m) => m.topic.contains('/action/')), isNotEmpty);
  for (final m in overheard) {
    expect(await Crypto.open(roomKey, m.payload), isNull, reason: m.topic);
    expect(m.payload.contains('werwolf'), isFalse);
  }

  // Neue Partie im selben Dorf.
  host.hostStore!.resetToLobby();
  await _until(() => bots.every((b) => b.room?.phase == Phase.lobby && b.secret.role == null), 'zurück in der Lobby');

  // Spielleiter geht → alle erfahren es.
  engine.dispose();
  await host.leaveRoom(code, isHost: true, inLobby: true);
  await _until(() => bots.skip(1).every((b) => b.room?.closed ?? false), 'Dorf geschlossen');

  for (final b in bots) {
    await b.dispose();
  }
  for (final r in repos.skip(1)) {
    await r.leaveRoom(code, isHost: false, inLobby: true);
  }
  await spy.disconnect();
}

Future<void> _until(bool Function() test, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!test()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung: $what');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  test('Komplette Partie über die Netzwerkschicht (im Speicher)', () async {
    final hub = MemoryHub();
    await playOverNetwork([() => MemoryTransport(hub)], joinTimeout: const Duration(milliseconds: 600));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('Komplette Partie über einen echten MQTT-Server (lokal)', () async {
    Process? broker;
    try {
      broker = await Process.start('mosquitto', ['-p', '18830']);
    } catch (_) {
      markTestSkipped('mosquitto ist nicht installiert');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    try {
      const local = Broker('127.0.0.1', tlsPort: 18831, plainPort: 18830);
      await playOverNetwork([() => MqttTransport(local)], timeScale: 0.02);
    } finally {
      broker.kill();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  // Prüft die öffentlichen Vermittlungsserver aus config.dart.
  // Nur mit freiem Internet sinnvoll:  WERWOLF_LIVE=1 flutter test test/network_test.dart
  group('Öffentliche Vermittlungsserver', () {
    final live = Platform.environment['WERWOLF_LIVE'] == '1';
    for (final b in kBrokers) {
      test('Partie über ${b.host}', () async {
        await playOverNetwork([() => MqttTransport(b)], n: 5, timeScale: 0.05, joinTimeout: const Duration(seconds: 5));
      }, skip: live ? false : 'nur mit WERWOLF_LIVE=1', timeout: const Timeout(Duration(minutes: 6)));
    }
  });
}
