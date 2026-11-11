import '../models/game_state.dart';
import '../models/roles.dart';

/// Bündelt alles, was ein Client über den Raum weiß, plus abgeleitete Regeln.
class RoomView {
  RoomView({
    required this.me,
    required this.room,
    required this.players,
    required this.secret,
    required this.myAction,
  });

  final String me;
  final RoomState room;
  final List<PlayerState> players;
  final SecretState secret;
  final Map<String, dynamic>? myAction;

  PlayerState? player(String uid) {
    for (final p in players) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  String name(String? uid) => uid == null ? '–' : (player(uid)?.name ?? '???');

  PlayerState? get mePlayer => player(me);
  bool get isHost => room.hostId == me;
  bool get meAlive => mePlayer?.alive ?? false;
  Role? get myRole => secret.role;
  bool get isGhost => room.inGame && !meAlive;

  bool get submitted => room.actionKey.isNotEmpty && myAction?['key'] == room.actionKey;

  List<PlayerState> get alive => players.where((p) => p.alive).toList();

  /// Bin ich im aktuellen Nachtschritt aktiv (wach)?
  bool get awakeAtNight {
    if (!room.isNight || !meAlive || myRole == null) return false;
    final r = myRole!;
    return switch (room.step) {
      NightStep.amor => r == Role.amor,
      NightStep.beschuetzer => r == Role.beschuetzer,
      NightStep.seherin => r == Role.seherin,
      NightStep.werwoelfe => r.isWolf || r == Role.maedchen,
      NightStep.weisserWerwolf => r == Role.weisserWerwolf,
      NightStep.hexe => r == Role.hexe,
      null => false,
    };
  }

  bool get peeking => room.isNight && room.step == NightStep.werwoelfe && meAlive && myRole == Role.maedchen;

  /// Augen zu: der Bildschirm wird dunkel.
  bool get sleeping => room.isNight && !awakeAtNight && !isGhost;

  bool isPackMate(String uid) =>
      myRole != null && myRole!.isWolf && secret.wolves.contains(uid) && uid != me;
}
