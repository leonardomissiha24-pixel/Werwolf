import 'roles.dart';

/// Öffentlicher Zustand eines Raums (rooms/{code}).
class RoomState {
  RoomState(this.code, Map<String, dynamic> d)
      : hostId = d['hostId'] as String? ?? '',
        phase = d['phase'] as String? ?? Phase.lobby,
        step = NightStep.fromId(d['step'] as String?),
        round = (d['round'] as num?)?.toInt() ?? 0,
        endsAt = (d['endsAt'] as num?)?.toInt(),
        narration = d['narration'] as String? ?? '',
        narrationId = (d['narrationId'] as num?)?.toInt() ?? 0,
        actionKey = d['actionKey'] as String? ?? '',
        actor = d['actor'] as String?,
        winner = d['winner'] as String?,
        winners = List<String>.from(d['winners'] as List? ?? const []),
        tally = Map<String, int>.from(
            (d['tally'] as Map? ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt()))),
        roleCounts = Map<String, int>.from(((d['settings'] as Map?)?['roles'] as Map? ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt()))),
        mayorEnabled = (d['settings'] as Map?)?['mayor'] as bool? ?? true,
        dayDuration = ((d['settings'] as Map?)?['day'] as num?)?.toInt() ?? 180,
        closed = d['closed'] as bool? ?? false;

  final String code;
  final String hostId;
  final String phase;
  final NightStep? step;
  final int round;
  final int? endsAt;
  final String narration;
  final int narrationId;
  final String actionKey;
  final String? actor;
  final String? winner;
  final List<String> winners;
  final Map<String, int> tally;
  final Map<String, int> roleCounts;
  final bool mayorEnabled;
  final int dayDuration;
  final bool closed;

  bool get isNight => phase == Phase.night;
  bool get inGame => phase != Phase.lobby && phase != Phase.end;
}

/// Öffentlicher Spielerzustand (rooms/{code}/players/{uid}).
class PlayerState {
  PlayerState(this.uid, Map<String, dynamic> d)
      : name = d['name'] as String? ?? '???',
        stamp = d['stamp'] as String? ?? '',
        joinedAt = (d['joinedAt'] as num?)?.toInt() ?? 0,
        alive = d['alive'] as bool? ?? true,
        revealedRole = Role.fromId(d['role'] as String?),
        mayor = d['mayor'] as bool? ?? false,
        canVote = d['canVote'] as bool? ?? true,
        lover = d['lover'] as bool? ?? false;

  final String uid;
  final String name;
  final String stamp;
  final int joinedAt;
  final bool alive;
  final Role? revealedRole;
  final bool mayor;
  final bool canVote;
  final bool lover;
}

/// Geheime Informationen eines Spielers (rooms/{code}/secrets/{uid}).
class SecretState {
  SecretState(Map<String, dynamic> d)
      : role = Role.fromId(d['role'] as String?),
        wolves = List<String>.from(d['wolves'] as List? ?? const []),
        lover = d['lover'] as String?,
        seen = (d['seen'] as Map? ?? const {})
            .map((k, v) => MapEntry(k as String, Role.fromId(v as String?) ?? Role.dorfbewohner)),
        witchVictim = (d['witch'] as Map?)?['victim'] as String?,
        healUsed = (d['witch'] as Map?)?['healUsed'] as bool? ?? false,
        poisonUsed = (d['witch'] as Map?)?['poisonUsed'] as bool? ?? false,
        pack = Map<String, String>.from(d['pack'] as Map? ?? const {}),
        protectedLast = d['protectedLast'] as String?,
        audience = Map<String, String>.from(d['audience'] as Map? ?? const {}),
        peek = List<String>.from(d['peek'] as List? ?? const []),
        ghost = d['ghost'] as bool? ?? false,
        allRoles = (d['allRoles'] as Map? ?? const {})
            .map((k, v) => MapEntry(k as String, Role.fromId(v as String?) ?? Role.dorfbewohner));

  SecretState.empty() : this(const {});

  final Role? role;

  /// Mitglieder des Rudels (nur für Werwölfe).
  final List<String> wolves;
  final String? lover;
  final Map<String, Role> seen;
  final String? witchVictim;
  final bool healUsed;
  final bool poisonUsed;

  /// Live-Stimmen des Rudels: uid -> Ziel.
  final Map<String, String> pack;
  final String? protectedLast;

  /// Für Werwölfe: wer darf nachts das Rudel sehen ('full' oder 'video').
  final Map<String, String> audience;

  /// Für das Mädchen: uids der Wölfe, deren Bild verschwommen gezeigt wird.
  final List<String> peek;

  /// Tote Spieler werden zu Geistern und sehen alle Rollen.
  final bool ghost;
  final Map<String, Role> allRoles;
}
