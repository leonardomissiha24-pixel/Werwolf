import 'package:material_ui/material_ui.dart';

import '../../models/roles.dart';
import '../../theme.dart';
import '../widgets/atmosphere.dart';
import '../widgets/role_sheet.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Atmosphere(
        showMoon: false,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Text('DIE ALTEN REGELN', textAlign: TextAlign.center, style: t.headlineMedium),
              const SizedBox(height: 10),
              const Center(child: BloodDivider()),
              const SizedBox(height: 16),
              Text(
                'Jeder Spieler sitzt vor seiner eigenen Kamera. Bei Tag sehen und hören sich alle. '
                'Bei Nacht erlöschen die Bilder – nur wer erwacht, sieht, was er sehen darf. '
                'Die Werwölfe erkennen einander über ihre Kameras und flüstern miteinander, '
                'während das Dorf schläft.',
                style: t.bodyLarge,
              ),
              const SizedBox(height: 14),
              _section(context, 'Die Nacht',
                  'Amor (nur in der ersten Nacht), Beschützer, Seherin, Werwölfe, Weißer Werwolf (jede zweite Nacht) und Hexe erwachen nacheinander. '
                      'Die Erzählerstimme führt durch die Nacht.'),
              _section(context, 'Der Tag',
                  'Die Toten der Nacht werden enthüllt. In der ersten Runde wählt das Dorf einen Bürgermeister, dessen Stimme doppelt zählt. '
                      'Dann wird beraten und offen abgestimmt. Bei Gleichstand stirbt niemand.'),
              _section(context, 'Die Toten',
                  'Wer stirbt, bleibt als Geist im Dorf: Er sieht alle Rollen und nachts das Rudel, aber sein Mikrofon bleibt stumm.'),
              _section(context, 'Der Sieg',
                  'Das Dorf siegt, wenn kein Werwolf mehr lebt. Die Werwölfe siegen, wenn nur noch Werwölfe leben. '
                      'Der Weiße Werwolf siegt allein. Bleiben nur die zwei Verliebten übrig, siegen sie gemeinsam.'),
              const SizedBox(height: 22),
              Text('DIE GESTALTEN', textAlign: TextAlign.center, style: t.titleLarge),
              const SizedBox(height: 14),
              for (final r in Role.values)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.85),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RoleSigil(icon: r.icon, size: 54, color: roleColor(r)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name.toUpperCase(), style: t.titleMedium?.copyWith(color: roleColor(r))),
                            Text(teamLabel(r),
                                style: const TextStyle(color: AppColors.ash, fontStyle: FontStyle.italic)),
                            const SizedBox(height: 6),
                            Text(r.description, style: t.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String text) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: t.titleMedium?.copyWith(color: AppColors.ember)),
          const SizedBox(height: 4),
          Text(text, style: t.bodyLarge),
        ],
      ),
    );
  }
}
