import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../config.dart';
import '../../models/game_state.dart';
import '../../models/roles.dart';
import '../../services/game_engine.dart';
import '../../services/narrator.dart';
import '../../services/room_repository.dart';
import '../../services/video_mesh.dart';
import '../../theme.dart';
import '../room_view.dart';
import '../widgets/atmosphere.dart';
import '../widgets/role_sheet.dart';
import '../widgets/video_tile.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.code});
  final String code;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final repo = RoomRepository.instance;
  late final String me = repo.uid;
  late final VideoMesh mesh = VideoMesh(code: widget.code, me: me);
  final narrator = Narrator();
  GameEngine? engine;

  RoomState? room;
  List<PlayerState> players = [];
  SecretState secret = SecretState.empty();
  Map<String, dynamic>? myAction;
  final List<StreamSubscription> _subs = [];

  final Set<String> _selection = {};
  bool _healToggle = false;
  String _selectionKey = '';
  int _spokenId = -1;
  bool _roleShown = false;
  bool _leaving = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    narrator.init();
    mesh.addListener(_rebuild);
    mesh.start();
    _subs.add(repo.watchRoom(widget.code).listen(_onRoom));
    _subs.add(repo.watchPlayers(widget.code).listen((p) {
      players = p;
      _sync();
    }));
    _subs.add(repo.watchSecret(widget.code).listen((s) {
      secret = s;
      _sync();
    }));
    _subs.add(repo.watchMyAction(widget.code).listen((a) {
      myAction = a;
      _rebuild();
    }));
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onRoom(RoomState? r) {
    if (r == null || r.closed) {
      if (!_leaving && mounted) {
        _leaving = true;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Der Spielleiter hat das Dorf verlassen.')));
        Navigator.of(context).pop();
      }
      return;
    }
    final prev = room;
    room = r;
    if (r.narrationId != _spokenId) {
      _spokenId = r.narrationId;
      if (prev != null) narrator.say(r.narration);
    }
    if (r.actionKey != _selectionKey) {
      _selectionKey = r.actionKey;
      _selection.clear();
      _healToggle = false;
    }
    if (r.phase == Phase.lobby) _roleShown = false;
    if (prev != null && prev.phase != r.phase && r.phase != Phase.lobby) {
      HapticFeedback.mediumImpact();
    }
    _sync();
  }

  RoomView? get view {
    final r = room;
    if (r == null) return null;
    return RoomView(me: me, room: r, players: players, secret: secret, myAction: myAction);
  }

  void _sync() {
    final v = view;
    if (v == null) return;
    mesh.syncPeers({for (final p in players) p.uid: p.stamp});
    mesh.setPolicies(send: (peer) => _sendGate(v, peer), play: (peer) => _playGate(v, peer));
    if (!_roleShown && v.room.inGame && v.myRole != null && mounted) {
      _roleShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showRoleSheet(context, v);
      });
    }
    _rebuild();
  }

  // ------------------------------------------------------------------
  // Wer sieht/hört wen?
  // ------------------------------------------------------------------

  MediaGate _sendGate(RoomView v, String peer) {
    final r = v.room;
    if (!r.inGame) return MediaGate.full;
    if (r.isNight) {
      if (r.step == NightStep.werwoelfe && v.meAlive && (v.myRole?.isWolf ?? false)) {
        return switch (v.secret.audience[peer]) {
          'full' => MediaGate.full,
          'video' => MediaGate.videoOnly,
          _ => MediaGate.none,
        };
      }
      return MediaGate.none;
    }
    return v.meAlive ? MediaGate.full : MediaGate.videoOnly;
  }

  MediaGate _playGate(RoomView v, String peer) {
    final r = v.room;
    if (!r.inGame) return MediaGate.full;
    final peerAlive = v.player(peer)?.alive ?? false;
    if (r.isNight) {
      if (r.step != NightStep.werwoelfe || !peerAlive) return MediaGate.none;
      if (v.isPackMate(peer) && v.meAlive) return MediaGate.full;
      if (v.isGhost && (v.secret.allRoles[peer]?.isWolf ?? false)) return MediaGate.videoOnly;
      if (v.peeking && v.secret.peek.contains(peer)) return MediaGate.videoOnly;
      return MediaGate.none;
    }
    return peerAlive ? MediaGate.full : MediaGate.videoOnly;
  }

  // ------------------------------------------------------------------
  // Aktionen
  // ------------------------------------------------------------------

  _ActionSpec? _spec(RoomView v) {
    final r = v.room;
    final role = v.myRole;
    bool alive(String u) => v.player(u)?.alive ?? false;
    bool aliveOthers(String u) => alive(u) && u != me;

    if (r.phase == Phase.night && v.meAlive && role != null) {
      switch (r.step) {
        case NightStep.amor when role == Role.amor:
          return _ActionSpec('Wähle zwei Seelen, die du aneinander bindest.', 2, alive, 'Pfeile abschießen',
              (s) => {'target': s[0], 'target2': s[1]});
        case NightStep.beschuetzer when role == Role.beschuetzer:
          return _ActionSpec(
              v.secret.protectedLast == null
                  ? 'Wen beschützt du in dieser Nacht?'
                  : 'Wen beschützt du? ${v.name(v.secret.protectedLast)} nicht erneut.',
              1,
              (u) => alive(u) && u != v.secret.protectedLast,
              'Wache halten',
              (s) => {'target': s[0]});
        case NightStep.seherin when role == Role.seherin:
          return _ActionSpec('Wessen wahre Gestalt willst du sehen?', 1, aliveOthers, 'In die Seele blicken',
              (s) => {'target': s[0]});
        case NightStep.werwoelfe when role.isWolf:
          return _ActionSpec('Wählt euer Opfer. Ihr seht und hört euch gegenseitig.', 1,
              (u) => alive(u) && !v.secret.wolves.contains(u), 'Zuschlagen', (s) => {'target': s[0]},
              allowChange: true);
        case NightStep.weisserWerwolf when role == Role.weisserWerwolf:
          return _ActionSpec('Willst du einen deiner Brüder reißen?', 1,
              (u) => alive(u) && u != me && v.secret.wolves.contains(u), 'Verraten', (s) => {'target': s[0]},
              skipLabel: 'Niemanden');
        case NightStep.hexe when role == Role.hexe:
          return _ActionSpec(
              v.secret.poisonUsed ? 'Dein Gift ist verbraucht.' : 'Tippe einen Spieler an, um ihn zu vergiften.',
              v.secret.poisonUsed ? 0 : 1,
              aliveOthers,
              'Bestätigen',
              (s) => {'heal': _healToggle, 'poison': s.isEmpty ? null : s[0], 'done': true},
              witch: true,
              optional: true);
        default:
          return null;
      }
    }
    if (r.phase == Phase.mayorElection && v.meAlive) {
      return _ActionSpec('Wer soll Bürgermeister werden?', 1, alive, 'Stimme abgeben', (s) => {'target': s[0]},
          allowChange: true);
    }
    if (r.phase == Phase.vote && v.meAlive && (v.mePlayer?.canVote ?? false)) {
      return _ActionSpec('Wen richtet das Dorf?', 1, aliveOthers, 'Verurteilen', (s) => {'target': s[0]},
          allowChange: true);
    }
    if (r.phase == Phase.hunter && r.actor == me) {
      return _ActionSpec('Wen nimmst du mit ins Grab?', 1, aliveOthers, 'Schießen', (s) => {'target': s[0]},
          skipLabel: 'Niemanden');
    }
    if (r.phase == Phase.successor && r.actor == me) {
      return _ActionSpec('Wer erbt dein Amt als Bürgermeister?', 1, aliveOthers, 'Amt übergeben',
          (s) => {'target': s[0]});
    }
    return null;
  }

  void _tapPlayer(RoomView v, _ActionSpec? spec, String uid) {
    if (spec == null || spec.max == 0) return;
    if (v.submitted && !spec.allowChange) return;
    if (!spec.selectable(uid)) return;
    setState(() {
      if (_selection.contains(uid)) {
        _selection.remove(uid);
      } else {
        if (_selection.length >= spec.max) _selection.remove(_selection.first);
        _selection.add(uid);
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _submit(RoomView v, _ActionSpec spec, {bool skip = false}) async {
    final payload = skip ? <String, dynamic>{'target': null, 'skip': true} : spec.payload(_selection.toList());
    await repo.submitAction(widget.code, v.room.actionKey, payload);
    HapticFeedback.heavyImpact();
  }

  // ------------------------------------------------------------------
  // Host
  // ------------------------------------------------------------------

  Future<void> _start(RoomView v) async {
    setState(() => _starting = true);
    try {
      engine?.dispose();
      engine = GameEngine(widget.code);
      await engine!.start(players, v.room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Start fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _newGame() async {
    engine?.dispose();
    engine = null;
    await GameEngine.resetToLobby(widget.code);
  }

  Future<bool> _confirmLeave() async {
    final v = view;
    final hostInGame = v != null && v.isHost;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('DAS DORF VERLASSEN?', style: TextStyle(fontFamily: AppText.display, letterSpacing: 2)),
        content: Text(hostInGame
            ? 'Du bist der Spielleiter. Wenn du gehst, endet die Nacht für alle.'
            : 'Willst du dich wirklich in den Wald davonstehlen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bleiben')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Gehen', style: TextStyle(color: AppColors.bloodBright))),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _leave() async {
    if (!await _confirmLeave()) return;
    _leaving = true;
    final v = view;
    await repo.leaveRoom(widget.code, isHost: v?.isHost ?? false, inLobby: !(v?.room.inGame ?? false));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    engine?.dispose();
    narrator.stop();
    mesh.removeListener(_rebuild);
    mesh.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final v = view;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: v == null
            ? const Atmosphere(
                child: Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.bloodBright)))
            : _body(v),
      ),
    );
  }

  Widget _body(RoomView v) {
    final r = v.room;
    final spec = _spec(v);
    final bloodMoon = r.isNight || (r.phase == Phase.end && r.winner != Winner.village);
    return Atmosphere(
      bloodMoon: bloodMoon,
      showMoon: r.isNight || r.phase == Phase.lobby,
      darkness: v.sleeping ? 1 : (r.isNight ? 0.35 : 0),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _Header(v: v, onLeave: _leave),
                Expanded(child: _grid(v, spec)),
                if (r.phase == Phase.lobby) _LobbyPanel(v: v, starting: _starting, onStart: () => _start(v)),
                if (r.inGame) _actionPanel(v, spec),
                _ControlBar(
                  mesh: mesh,
                  narrator: narrator,
                  onRole: v.myRole == null ? null : () => showRoleSheet(context, v),
                  onRefresh: _rebuild,
                ),
              ],
            ),
            if (v.sleeping) _SleepOverlay(v: v),
            if (v.peeking) _PeekPanel(mesh: mesh, uids: v.secret.peek),
            if (r.phase == Phase.end) _EndPanel(v: v, onNewGame: v.isHost ? _newGame : null, onLeave: _leave),
          ],
        ),
      ),
    );
  }

  Widget _grid(RoomView v, _ActionSpec? spec) {
    final r = v.room;
    final list = v.players;
    if (list.isEmpty) return const SizedBox();
    return LayoutBuilder(builder: (context, c) {
      const gap = 6.0;
      final n = list.length;
      var bestCols = 1;
      var bestW = 0.0;
      for (var cols = 1; cols <= 4; cols++) {
        final rows = (n / cols).ceil();
        final wByWidth = (c.maxWidth - gap * (cols + 1)) / cols;
        final wByHeight = ((c.maxHeight - gap * (rows + 1)) / rows) * 3 / 4;
        final w = min(wByWidth, wByHeight);
        if (w > bestW) {
          bestW = w;
          bestCols = cols;
        }
      }
      final tileW = max(60.0, bestW);
      final tileH = tileW * 4 / 3;
      final packVotes = <String, int>{};
      for (final t in v.secret.pack.values) {
        packVotes[t] = (packVotes[t] ?? 0) + 1;
      }

      return Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(gap),
            child: SizedBox(
              width: bestCols * tileW + (bestCols - 1) * gap,
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                alignment: WrapAlignment.center,
                children: [
                  for (final p in list)
                    SizedBox(
                      width: tileW,
                      height: tileH,
                      child: _tile(v, spec, p, r, packVotes),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _tile(RoomView v, _ActionSpec? spec, PlayerState p, RoomState r, Map<String, int> packVotes) {
    final isMe = p.uid == me;
    final gate = isMe ? MediaGate.full : mesh.playGate(p.uid);
    final renderer = isMe ? (mesh.hasLocalVideo ? mesh.localRenderer : null) : mesh.rendererFor(p.uid);
    final selectable = spec != null && spec.max > 0 && spec.selectable(p.uid) && (!v.submitted || spec.allowChange);

    // Geheime Markierungen (nur auf dem eigenen Bildschirm sichtbar)
    String? tag;
    Color tagColor = AppColors.bloodBright;
    final ghostRole = v.isGhost ? v.secret.allRoles[p.uid] : null;
    if (r.phase == Phase.lobby && p.uid == r.hostId) {
      tag = 'Spielleiter';
      tagColor = AppColors.ember;
    } else if (v.isPackMate(p.uid)) {
      tag = 'Rudel';
    } else if (v.secret.lover == p.uid) {
      tag = 'Verliebt';
      tagColor = const Color(0xFFD86A7A);
    } else if (v.secret.seen[p.uid] != null && p.revealedRole == null) {
      final seen = v.secret.seen[p.uid]!;
      tag = 'Vision: ${seen.name}';
      tagColor = seen.isWolf ? AppColors.bloodBright : AppColors.frost;
    } else if (ghostRole != null && p.revealedRole == null) {
      tag = ghostRole.name;
      tagColor = ghostRole.isWolf ? AppColors.bloodBright : AppColors.ash;
    }
    if (r.isNight && r.step == NightStep.hexe && v.myRole == Role.hexe && v.secret.witchVictim == p.uid) {
      tag = 'Opfer der Wölfe';
    }

    int votes = 0;
    if (r.phase == Phase.vote || r.phase == Phase.mayorElection || (r.phase == Phase.dawn && r.tally.isNotEmpty)) {
      votes = r.tally[p.uid] ?? 0;
    } else if (r.isNight && r.step == NightStep.werwoelfe && (v.myRole?.isWolf ?? false)) {
      votes = packVotes[p.uid] ?? 0;
    }

    final showVideo = isMe ? !mesh.cameraOff : gate.video;
    return VideoTile(
      name: p.name,
      renderer: renderer,
      showVideo: showVideo && !(r.isNight && !isMe && !gate.video),
      mirror: isMe,
      isSelf: isMe,
      dead: !p.alive,
      mayor: p.mayor,
      revealedRole: p.revealedRole,
      selected: _selection.contains(p.uid) || (v.submitted && myAction?['target'] == p.uid && _selection.isEmpty),
      onTap: selectable ? () => _tapPlayer(v, spec, p.uid) : null,
      votes: votes,
      tag: tag,
      tagColor: tagColor,
      muted: isMe ? mesh.micMuted : (!gate.audio && r.inGame),
      connecting: !isMe && renderer == null && r.phase == Phase.lobby,
      dim: spec != null && spec.max > 0 && !spec.selectable(p.uid),
    );
  }

  Widget _actionPanel(RoomView v, _ActionSpec? spec) {
    final r = v.room;
    final children = <Widget>[];

    if (spec != null) {
      children.add(Text(spec.prompt, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)));
      if (spec.witch) {
        final victim = v.secret.witchVictim;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            victim == null
                ? 'Die Wölfe haben heute niemanden gerissen.'
                : 'Die Wölfe haben ${v.name(victim)} gewählt.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.bloodBright, fontSize: 18),
          ),
        ));
        if (victim != null && !v.secret.healUsed && !v.submitted) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GothicButton(
              dense: true,
              primary: _healToggle,
              icon: _healToggle ? Icons.check : Icons.healing,
              label: _healToggle ? 'Heiltrank wird genutzt' : 'Heiltrank nutzen',
              onPressed: () => setState(() => _healToggle = !_healToggle),
            ),
          ));
        }
      }
      final submittedFinal = v.submitted && !spec.allowChange;
      if (submittedFinal) {
        String text = 'Deine Entscheidung ist gefallen.';
        final t = myAction?['target'] as String?;
        if (r.step == NightStep.seherin && t != null) {
          final seen = v.secret.seen[t];
          text = seen == null ? 'Die Nebel lichten sich …' : '${v.name(t)} ist: ${seen.name.toUpperCase()}';
        }
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppText.display, letterSpacing: 1.5, color: AppColors.ember)),
        ));
      } else {
        final enough = spec.optional ? _selection.length <= spec.max : _selection.length == spec.max;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: GothicButton(
                  dense: true,
                  icon: Icons.bloodtype,
                  label: _selection.isEmpty || spec.witch
                      ? spec.confirm
                      : '${spec.confirm}: ${_selection.map(v.name).join(' & ')}',
                  onPressed: enough ? () => _submit(v, spec) : null,
                ),
              ),
              if (spec.skipLabel != null) ...[
                const SizedBox(width: 8),
                GothicButton(
                    dense: true, primary: false, label: spec.skipLabel!, onPressed: () => _submit(v, spec, skip: true)),
              ],
            ],
          ),
        ));
        if (v.submitted && spec.allowChange) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Deine Stimme: ${v.name(myAction?['target'] as String?)} — du kannst sie noch ändern.',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.ash)),
          ));
        }
      }
    } else if (r.phase == Phase.day && v.isHost) {
      children.add(GothicButton(
        dense: true,
        icon: Icons.gavel,
        label: 'Zur Abstimmung',
        onPressed: () => engine?.skip(),
      ));
    } else if (v.isGhost && r.inGame) {
      children.add(const Text('Du bist tot. Beobachte schweigend.',
          textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.ash)));
    } else if ((r.phase == Phase.hunter || r.phase == Phase.successor) && r.actor != null) {
      children.add(Text('${v.name(r.actor)} trifft eine letzte Entscheidung …',
          textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.ash)));
    } else if (r.phase == Phase.vote && !(v.mePlayer?.canVote ?? true)) {
      children.add(const Text('Als enttarnter Dorfdepp darfst du nicht mehr abstimmen.',
          textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.ash)));
    }

    if (children.isEmpty) return const SizedBox(height: 4);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.night.withValues(alpha: 0.92),
        border: Border.all(color: spec != null ? AppColors.blood : AppColors.line),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ActionSpec {
  _ActionSpec(this.prompt, this.max, this.selectable, this.confirm, this.payload,
      {this.allowChange = false, this.skipLabel, this.witch = false, this.optional = false});
  final String prompt;
  final int max;
  final bool Function(String uid) selectable;
  final String confirm;
  final Map<String, dynamic> Function(List<String> selection) payload;
  final bool allowChange;
  final String? skipLabel;
  final bool witch;
  final bool optional;
}

// ======================================================================
// Kopfzeile mit Phase, Countdown und Erzähltext
// ======================================================================

class _Header extends StatelessWidget {
  const _Header({required this.v, required this.onLeave});
  final RoomView v;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final r = v.room;
    final title = r.phase == Phase.lobby ? 'Dorf ${r.code}' : Phase.title(r.phase, r.step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.close, color: AppColors.ash), onPressed: onLeave),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: AppText.display, fontSize: 17, letterSpacing: 3, fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(
                width: 48,
                child: r.endsAt != null && r.inGame
                    ? _Countdown(endsAt: r.endsAt!)
                    : (r.inGame ? Text('${r.round}', textAlign: TextAlign.right) : null),
              ),
            ],
          ),
          if (r.phase == Phase.lobby)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                children: [
                  SelectableText(
                    r.code,
                    style: const TextStyle(
                        fontFamily: AppText.display,
                        fontSize: 34,
                        letterSpacing: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.bloodBright),
                  ),
                  const Text('Nenne diesen Code den anderen Seelen.',
                      style: TextStyle(color: AppColors.ash, fontStyle: FontStyle.italic)),
                ],
              ),
            )
          else if (r.narration.isNotEmpty)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              child: Padding(
                key: ValueKey(r.narrationId),
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Text(
                  r.narration,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontStyle: FontStyle.italic, height: 1.3),
                ),
              ),
            ),
          const BloodDivider(width: 240),
        ],
      ),
    );
  }
}

class _Countdown extends StatefulWidget {
  const _Countdown({required this.endsAt});
  final int endsAt;
  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = max(0, ((widget.endsAt - DateTime.now().millisecondsSinceEpoch) / 1000).ceil());
    final text = s >= 60 ? '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}' : '$s';
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: AppText.display,
        fontWeight: FontWeight.w700,
        color: s <= 10 ? AppColors.bloodBright : AppColors.ash,
      ),
    );
  }
}

// ======================================================================
// Lobby
// ======================================================================

class _LobbyPanel extends StatelessWidget {
  const _LobbyPanel({required this.v, required this.starting, required this.onStart});
  final RoomView v;
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final n = v.players.length;
    final roles = v.room.roleCounts;
    final total = roles.values.fold<int>(0, (a, b) => a + b);
    final wolves = (roles[Role.werwolf.id] ?? 0) + (roles[Role.weisserWerwolf.id] ?? 0);
    final minPlayers = kDebugMode ? kMinPlayersDebug : kMinPlayersRelease;
    String? problem;
    if (n < minPlayers) {
      problem = 'Mindestens $minPlayers Spieler nötig ($n anwesend).';
    } else if (total != n) {
      problem = 'Rollen: $total – Spieler: $n. Passe die Verteilung an.';
    } else if ((roles[Role.werwolf.id] ?? 0) < 1) {
      problem = 'Ohne Werwolf keine Nacht.';
    } else if (wolves * 2 >= n) {
      problem = 'Zu viele Werwölfe für dieses Dorf.';
    }

    final summary = roles.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.value}× ${Role.fromId(e.key)?.name ?? e.key}')
        .join(' · ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.night.withValues(alpha: 0.92),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(summary.isEmpty ? 'Noch keine Rollen gewählt.' : summary,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.ash)),
          const SizedBox(height: 8),
          if (v.isHost) ...[
            Row(
              children: [
                Expanded(
                  child: GothicButton(
                    dense: true,
                    primary: false,
                    icon: Icons.tune,
                    label: 'Rollen',
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _RoleConfigSheet(code: v.room.code, initial: v.room, playerCount: n),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GothicButton(
                    dense: true,
                    icon: Icons.nights_stay,
                    label: starting ? '…' : 'Nacht beginnen',
                    onPressed: problem == null && !starting ? onStart : null,
                  ),
                ),
              ],
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(problem, style: const TextStyle(color: AppColors.bloodBright)),
              ),
          ] else
            const Text('Warte, bis der Spielleiter die Nacht beginnen lässt …',
                textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _RoleConfigSheet extends StatefulWidget {
  const _RoleConfigSheet({required this.code, required this.initial, required this.playerCount});
  final String code;
  final RoomState initial;
  final int playerCount;

  @override
  State<_RoleConfigSheet> createState() => _RoleConfigSheetState();
}

class _RoleConfigSheetState extends State<_RoleConfigSheet> {
  late Map<String, int> roles = widget.initial.roleCounts.isEmpty
      ? Role.defaultsFor(widget.playerCount)
      : {...widget.initial.roleCounts};
  late bool mayor = widget.initial.mayorEnabled;
  late int day = widget.initial.dayDuration;

  int get total => roles.values.fold(0, (a, b) => a + b);

  void _save() =>
      RoomRepository.instance.updateSettings(widget.code, Map.of(roles)..removeWhere((_, v) => v == 0), mayor, day);

  @override
  void initState() {
    super.initState();
    if (widget.initial.roleCounts.isEmpty) _save();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          Text('DIE GESTALTEN DIESER NACHT',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('$total Rollen für ${widget.playerCount} Spieler',
              textAlign: TextAlign.center,
              style: TextStyle(color: total == widget.playerCount ? AppColors.ash : AppColors.bloodBright)),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.auto_fix_high, size: 18, color: AppColors.ember),
              label: const Text('Empfohlene Verteilung', style: TextStyle(color: AppColors.ember)),
              onPressed: () {
                setState(() => roles = Role.defaultsFor(widget.playerCount));
                _save();
              },
            ),
          ),
          for (final r in Role.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  RoleSigil(icon: r.icon, size: 40, color: roleColor(r)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: const TextStyle(fontFamily: AppText.display, fontSize: 14)),
                        Text(r.short, style: const TextStyle(color: AppColors.ash, fontSize: 14)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    onPressed: (roles[r.id] ?? 0) > 0
                        ? () {
                            setState(() => roles[r.id] = (roles[r.id] ?? 0) - 1);
                            _save();
                          }
                        : null,
                  ),
                  SizedBox(
                    width: 20,
                    child: Text('${roles[r.id] ?? 0}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: AppText.display, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: (r == Role.werwolf || r == Role.dorfbewohner || (roles[r.id] ?? 0) == 0)
                        ? () {
                            setState(() => roles[r.id] = (roles[r.id] ?? 0) + 1);
                            _save();
                          }
                        : null,
                  ),
                ],
              ),
            ),
          const Divider(color: AppColors.line, height: 28),
          SwitchListTile(
            value: mayor,
            activeThumbColor: AppColors.bloodBright,
            title: const Text('Bürgermeister wählen'),
            subtitle: const Text('Seine Stimme zählt doppelt.', style: TextStyle(color: AppColors.ash)),
            onChanged: (b) {
              setState(() => mayor = b);
              _save();
            },
          ),
          const SizedBox(height: 6),
          const Text('Dauer der Beratung am Tag', style: TextStyle(color: AppColors.ash)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final s in [120, 180, 300, 420])
                ChoiceChip(
                  label: Text('${s ~/ 60} Min'),
                  selected: day == s,
                  selectedColor: AppColors.blood,
                  shape: const RoundedRectangleBorder(side: BorderSide(color: AppColors.line)),
                  onSelected: (_) {
                    setState(() => day = s);
                    _save();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Bedienleiste
// ======================================================================

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.mesh, required this.narrator, required this.onRole, required this.onRefresh});
  final VideoMesh mesh;
  final Narrator narrator;
  final VoidCallback? onRole;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, String tip, VoidCallback? f, {bool active = false}) => IconButton(
          tooltip: tip,
          onPressed: f,
          icon: Icon(i, color: active ? AppColors.bloodBright : AppColors.bone, size: 22),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          btn(mesh.micMuted ? Icons.mic_off : Icons.mic, 'Mikrofon', mesh.toggleMic, active: mesh.micMuted),
          btn(mesh.cameraOff ? Icons.videocam_off : Icons.videocam, 'Kamera', mesh.toggleCamera,
              active: mesh.cameraOff),
          btn(Icons.cameraswitch, 'Kamera wechseln', mesh.hasLocalVideo ? mesh.switchCamera : null),
          btn(narrator.enabled ? Icons.record_voice_over : Icons.voice_over_off, 'Erzähler', () {
            narrator.enabled = !narrator.enabled;
            if (!narrator.enabled) narrator.stop();
            onRefresh();
          }, active: !narrator.enabled),
          TextButton.icon(
            onPressed: onRole,
            icon: const Icon(Icons.style, size: 18, color: AppColors.ember),
            label: const Text('ROLLE',
                style: TextStyle(fontFamily: AppText.display, letterSpacing: 2, color: AppColors.ember)),
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// Nacht-Overlays
// ======================================================================

class _SleepOverlay extends StatelessWidget {
  const _SleepOverlay({required this.v});
  final RoomView v;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.86),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bedtime, size: 44, color: Color(0xFF5A1414)),
              const SizedBox(height: 18),
              const Text('DU SCHLÄFST',
                  style: TextStyle(fontFamily: AppText.display, letterSpacing: 6, fontSize: 20, color: AppColors.ash)),
              const SizedBox(height: 10),
              Text(
                v.room.step == null ? 'Schließe die Augen.' : '${v.room.step!.title} …',
                textAlign: TextAlign.center,
                style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF6E665E), fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Deine Kamera ist für alle erloschen.',
                style: TextStyle(color: Color(0xFF4E4842), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeekPanel extends StatelessWidget {
  const _PeekPanel({required this.mesh, required this.uids});
  final VideoMesh mesh;
  final List<String> uids;

  @override
  Widget build(BuildContext context) {
    final renderers = uids.map(mesh.rendererFor).whereType<Object>().toList();
    return Positioned(
      left: 12,
      right: 12,
      top: 120,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          border: Border.all(color: AppColors.blood),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('DURCH DIE FINGER …',
                style: TextStyle(fontFamily: AppText.display, letterSpacing: 4, color: AppColors.ember)),
            const SizedBox(height: 4),
            const Text('Verschwommene Gestalten im Mondlicht. Wer sind sie?',
                textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.ash)),
            const SizedBox(height: 10),
            if (renderers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nur Dunkelheit.', style: TextStyle(color: AppColors.ash)),
              )
            else
              SizedBox(
                height: 130,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final uid in uids)
                      if (mesh.rendererFor(uid) != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SizedBox(width: 96, child: PeekView(renderer: mesh.rendererFor(uid)!)),
                        ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Spielende
// ======================================================================

class _EndPanel extends StatelessWidget {
  const _EndPanel({required this.v, required this.onNewGame, required this.onLeave});
  final RoomView v;
  final VoidCallback? onNewGame;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final r = v.room;
    final iWon = r.winners.contains(v.me);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            children: [
              Text(
                Winner.title(r.winner ?? Winner.none).toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: r.winner == Winner.village ? AppColors.bone : AppColors.bloodBright,
                  shadows: const [Shadow(color: AppColors.blood, blurRadius: 20)],
                ),
              ),
              const SizedBox(height: 10),
              const BloodDivider(width: 220),
              const SizedBox(height: 12),
              Text(r.narration,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic)),
              const SizedBox(height: 10),
              Text(iWon ? 'DU HAST ÜBERLEBT – ODER GESIEGT.' : 'DU HAST VERLOREN.',
                  style: TextStyle(
                      fontFamily: AppText.display,
                      letterSpacing: 3,
                      color: iWon ? AppColors.ember : AppColors.ash)),
              const SizedBox(height: 20),
              for (final p in v.players)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: r.winners.contains(p.uid) ? AppColors.ember : AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(p.revealedRole?.icon ?? Icons.help_outline,
                          size: 20, color: (p.revealedRole?.isWolf ?? false) ? AppColors.bloodBright : AppColors.bone),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.name + (p.lover ? '  ♥' : ''),
                          style: TextStyle(
                            fontSize: 18,
                            color: p.alive ? AppColors.bone : AppColors.ash,
                            decoration: p.alive ? null : TextDecoration.lineThrough,
                            decorationColor: AppColors.blood,
                          ),
                        ),
                      ),
                      Text(p.revealedRole?.name ?? '',
                          style: const TextStyle(fontFamily: AppText.display, fontSize: 12, letterSpacing: 1)),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              if (onNewGame != null) ...[
                GothicButton(label: 'Eine neue Nacht', icon: Icons.replay, onPressed: onNewGame),
                const SizedBox(height: 10),
              ] else
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Der Spielleiter kann eine neue Nacht beginnen.',
                      style: TextStyle(color: AppColors.ash, fontStyle: FontStyle.italic)),
                ),
              GothicButton(label: 'Das Dorf verlassen', primary: false, onPressed: onLeave),
            ],
          ),
        ),
      ),
    );
  }
}
