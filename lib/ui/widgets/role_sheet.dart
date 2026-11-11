import 'package:material_ui/material_ui.dart';

import '../../models/roles.dart';
import '../../theme.dart';
import '../room_view.dart';
import 'atmosphere.dart';

String teamLabel(Role r) => switch (r.team) {
      Team.village => 'Gehört zum Dorf',
      Team.wolves => 'Gehört zum Rudel',
      Team.solo => 'Kämpft allein',
    };

Color roleColor(Role r) => switch (r.team) {
      Team.wolves => AppColors.bloodBright,
      Team.solo => AppColors.frost,
      Team.village => AppColors.bone,
    };

/// Zeigt die eigene Rolle samt geheimem Wissen.
Future<void> showRoleSheet(BuildContext context, RoomView v) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoleSheet(v),
  );
}

class _RoleSheet extends StatelessWidget {
  const _RoleSheet(this.v);
  final RoomView v;

  @override
  Widget build(BuildContext context) {
    final role = v.myRole;
    final s = v.secret;
    final knowledge = <String>[
      if (role != null && role.isWolf && s.wolves.length > 1)
        'Dein Rudel: ${s.wolves.where((w) => w != v.me).map(v.name).join(', ')}',
      if (s.lover != null) 'Dein Herz gehört ${v.name(s.lover)}. Stirbt einer, stirbt auch der andere.',
      for (final e in s.seen.entries) 'Vision: ${v.name(e.key)} ist ${e.value.name}.',
      if (role == Role.hexe)
        'Heiltrank: ${s.healUsed ? 'verbraucht' : 'bereit'} · Gifttrank: ${s.poisonUsed ? 'verbraucht' : 'bereit'}',
      if (role == Role.beschuetzer && s.protectedLast != null)
        'Letzte Nacht beschützt: ${v.name(s.protectedLast)} (heute nicht erneut möglich)',
      if (v.mePlayer?.mayor ?? false) 'Du bist Bürgermeister. Deine Stimme zählt doppelt.',
      if (!(v.mePlayer?.canVote ?? true)) 'Du wurdest als Dorfdepp enttarnt und darfst nicht mehr abstimmen.',
      if (v.isGhost) 'Du bist tot. Als Geist siehst du alle Rollen – aber du schweigst.',
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.night,
        border: Border(top: BorderSide(color: AppColors.blood)),
      ),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (role == null)
              const Text('Noch keine Rolle.', style: TextStyle(fontSize: 18))
            else ...[
              RoleSigil(icon: role.icon, size: 96, color: roleColor(role), glow: AppColors.blood),
              const SizedBox(height: 18),
              Text(
                role.name.toUpperCase(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: roleColor(role)),
              ),
              const SizedBox(height: 6),
              Text(teamLabel(role).toUpperCase(),
                  style: const TextStyle(
                      fontFamily: AppText.display, fontSize: 11, letterSpacing: 3, color: AppColors.ash)),
              const SizedBox(height: 14),
              const BloodDivider(),
              const SizedBox(height: 14),
              Text(role.description, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            ],
            if (knowledge.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text('DEIN WISSEN',
                  style: TextStyle(
                      fontFamily: AppText.display, letterSpacing: 3, fontSize: 12, color: AppColors.ember)),
              const SizedBox(height: 8),
              for (final k in knowledge)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('— $k', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
                ),
            ],
            const SizedBox(height: 22),
            const Text(
              'Halte dein Display verdeckt. Niemand darf deine Karte sehen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.ash),
            ),
          ],
        ),
      ),
    );
  }
}
