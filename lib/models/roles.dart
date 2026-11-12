import 'package:material_ui/material_ui.dart';

enum Team { village, wolves, solo }

/// Alle Rollen des Spiels. Die [id] wird im Spielzustand übertragen.
enum Role {
  werwolf(
    id: 'werwolf',
    name: 'Werwolf',
    team: Team.wolves,
    icon: Icons.pets,
    short: 'Erwacht jede Nacht mit dem Rudel und reißt einen Dorfbewohner.',
    description:
        'Nachts öffnen die Werwölfe ihre Augen – und nur sie sehen und hören '
        'einander über die Kamera. Gemeinsam wählen sie ein Opfer. Tagsüber '
        'mischen sie sich unter das Dorf und lügen. Sie gewinnen, wenn kein '
        'Dorfbewohner mehr lebt.',
  ),
  weisserWerwolf(
    id: 'weisser_werwolf',
    name: 'Weißer Werwolf',
    team: Team.solo,
    icon: Icons.ac_unit,
    short: 'Jagt mit dem Rudel – und verrät es jede zweite Nacht.',
    description:
        'Gehört scheinbar zum Rudel und erwacht mit den Werwölfen. Jede zweite '
        'Nacht erwacht er allein und darf einen anderen Werwolf töten. Er gewinnt '
        'nur, wenn er als Letzter übrig bleibt.',
  ),
  dorfbewohner(
    id: 'dorfbewohner',
    name: 'Dorfbewohner',
    team: Team.village,
    icon: Icons.cottage,
    short: 'Keine Gabe außer Misstrauen und der Stimme beim Richten.',
    description:
        'Ein einfacher Mensch ohne besondere Fähigkeit. Beobachte Gesichter, '
        'Blicke und Zögern in der Kamera – und richte die Richtigen.',
  ),
  seherin(
    id: 'seherin',
    name: 'Seherin',
    team: Team.village,
    icon: Icons.visibility,
    short: 'Erblickt jede Nacht die wahre Gestalt eines Spielers.',
    description:
        'Erwacht jede Nacht und wählt einen Spieler. Die Karten verraten ihr '
        'dessen wahre Rolle. Wer zu laut über seine Visionen spricht, stirbt früh.',
  ),
  hexe(
    id: 'hexe',
    name: 'Hexe',
    team: Team.village,
    icon: Icons.science,
    short: 'Ein Heiltrank, ein Gifttrank – einmal pro Spiel.',
    description:
        'Erfährt jede Nacht, wen die Werwölfe gerissen haben. Sie kann das Opfer '
        'einmal im Spiel mit dem Heiltrank retten und einmal im Spiel einen '
        'Spieler mit dem Gifttrank töten.',
  ),
  jaeger(
    id: 'jaeger',
    name: 'Jäger',
    team: Team.village,
    icon: Icons.gps_fixed,
    short: 'Reißt im Tod einen anderen mit sich.',
    description:
        'Stirbt der Jäger – ganz gleich wie –, legt er mit dem letzten Atemzug '
        'an und nimmt einen Spieler seiner Wahl mit ins Grab.',
  ),
  amor(
    id: 'amor',
    name: 'Amor',
    team: Team.village,
    icon: Icons.favorite,
    short: 'Bindet in der ersten Nacht zwei Seelen aneinander.',
    description:
        'Wählt in der ersten Nacht zwei Verliebte. Stirbt einer, stirbt der '
        'andere vor Kummer. Sind die Verliebten am Ende allein übrig, gewinnen '
        'sie gemeinsam – selbst wenn einer von ihnen ein Werwolf ist.',
  ),
  beschuetzer(
    id: 'beschuetzer',
    name: 'Beschützer',
    team: Team.village,
    icon: Icons.shield,
    short: 'Bewacht jede Nacht eine Tür vor den Werwölfen.',
    description:
        'Wählt jede Nacht einen Spieler (auch sich selbst), der vor dem Angriff '
        'der Werwölfe geschützt ist. Er darf nicht zweimal hintereinander '
        'dieselbe Person schützen.',
  ),
  maedchen(
    id: 'maedchen',
    name: 'Kleines Mädchen',
    team: Team.village,
    icon: Icons.blur_on,
    short: 'Blinzelt nachts durch die Finger – auf die Kameras der Wölfe.',
    description:
        'Während die Werwölfe erwachen, sieht das Mädchen deren Kamerabilder – '
        'verschwommen, ohne Ton und ohne Namen. Wer erkennt sie wieder, wenn '
        'der Morgen graut?',
  ),
  dorfaeltester(
    id: 'dorfaeltester',
    name: 'Dorfältester',
    team: Team.village,
    icon: Icons.hourglass_bottom,
    short: 'Überlebt den ersten Angriff der Werwölfe.',
    description:
        'Zäh wie altes Leder: Der erste Angriff der Werwölfe tötet ihn nicht. '
        'Gegen Gift, den Jäger oder das Urteil des Dorfes ist er machtlos.',
  ),
  dorfdepp(
    id: 'dorfdepp',
    name: 'Dorfdepp',
    team: Team.village,
    icon: Icons.psychology_alt,
    short: 'Wird beim Richten verschont – verliert aber seine Stimme.',
    description:
        'Wird er vom Dorf zum Tode verurteilt, erkennt man ihn und lässt ihn '
        'leben. Ab dann darf er nicht mehr abstimmen.',
  );

  const Role({
    required this.id,
    required this.name,
    required this.team,
    required this.icon,
    required this.short,
    required this.description,
  });

  final String id;
  final String name;
  final Team team;
  final IconData icon;
  final String short;
  final String description;

  bool get isWolf => this == Role.werwolf || this == Role.weisserWerwolf;

  static Role? fromId(String? id) {
    if (id == null) return null;
    for (final r in Role.values) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Empfohlene Rollenverteilung für [n] Spieler.
  static Map<String, int> defaultsFor(int n) {
    final m = <String, int>{};
    void add(Role r, [int c = 1]) => m[r.id] = (m[r.id] ?? 0) + c;
    final wolves = n <= 6 ? 1 : (n <= 8 ? 2 : (n <= 11 ? 3 : 4));
    add(Role.werwolf, wolves);
    add(Role.seherin);
    if (n >= 6) add(Role.hexe);
    if (n >= 7) add(Role.jaeger);
    if (n >= 8) add(Role.amor);
    if (n >= 9) add(Role.beschuetzer);
    if (n >= 10) add(Role.maedchen);
    if (n >= 11) add(Role.dorfaeltester);
    if (n >= 12) add(Role.dorfdepp);
    final used = m.values.fold<int>(0, (a, b) => a + b);
    if (n - used > 0) add(Role.dorfbewohner, n - used);
    return m;
  }
}

/// Nachtschritte in der Reihenfolge, in der sie ablaufen.
enum NightStep {
  amor('amor', 'Amor erwacht',
      'Amor erwacht und spannt den Bogen. Zwei Seelen werden fortan aneinander gebunden sein – im Leben wie im Tod.'),
  beschuetzer('beschuetzer', 'Der Beschützer wacht',
      'Der Beschützer erwacht. Vor wessen Tür wird er in dieser Nacht Wache halten?'),
  seherin('seherin', 'Die Seherin erwacht',
      'Die Seherin erwacht. Ihr Blick durchdringt den Nebel und sucht nach der Wahrheit.'),
  werwoelfe('werwoelfe', 'Die Werwölfe erwachen',
      'Die Werwölfe erwachen. Sie erkennen einander im Dunkeln … und wählen ihr Opfer.'),
  weisserWerwolf('weisser_werwolf', 'Der Weiße Werwolf',
      'Der Weiße Werwolf erwacht allein. Hunger kennt keine Treue.'),
  hexe('hexe', 'Die Hexe erwacht',
      'Die Hexe erwacht. Leben oder Tod – beides ruht in ihren Phiolen.');

  const NightStep(this.id, this.title, this.narration);
  final String id;
  final String title;
  final String narration;

  static NightStep? fromId(String? id) {
    for (final s in NightStep.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// Spielphasen (Feld `phase` im Raum-Dokument).
class Phase {
  static const lobby = 'lobby';
  static const night = 'night';
  static const dawn = 'dawn';
  static const mayorElection = 'mayor';
  static const day = 'day';
  static const vote = 'vote';
  static const hunter = 'hunter';
  static const successor = 'successor';
  static const end = 'end';

  static bool isDaylight(String p) =>
      p == dawn || p == mayorElection || p == day || p == vote || p == hunter || p == successor;

  static String title(String p, NightStep? step) {
    switch (p) {
      case lobby:
        return 'Versammlung';
      case night:
        return step?.title ?? 'Die Nacht';
      case dawn:
        return 'Morgengrauen';
      case mayorElection:
        return 'Wahl des Bürgermeisters';
      case day:
        return 'Der Tag';
      case vote:
        return 'Das Gericht';
      case hunter:
        return 'Der letzte Schuss';
      case successor:
        return 'Das Erbe';
      case end:
        return 'Das Ende';
    }
    return '';
  }
}

class Winner {
  static const village = 'village';
  static const wolves = 'wolves';
  static const white = 'white';
  static const lovers = 'lovers';
  static const none = 'none';

  static String title(String w) => switch (w) {
        village => 'Das Dorf siegt',
        wolves => 'Die Werwölfe siegen',
        white => 'Der Weiße Werwolf siegt',
        lovers => 'Die Liebenden siegen',
        _ => 'Niemand überlebt',
      };

  static String narration(String w) => switch (w) {
        village =>
          'Die letzte Bestie ist gefallen. Die Sonne geht über stillen Gassen auf – doch niemand wird diese Nächte je vergessen.',
        wolves =>
          'Die Werwölfe haben das Dorf verschlungen. Nur noch ihr Heulen hallt durch die leeren Gassen.',
        white =>
          'Der Weiße Werwolf steht allein im Blut seiner Brüder. Das Dorf gehört ihm.',
        lovers =>
          'Nur die Liebenden sind geblieben. Allein in einem toten Dorf – aber zusammen.',
        _ => 'Niemand hat überlebt. Über dem Dorf liegt nur noch Nebel.',
      };
}
