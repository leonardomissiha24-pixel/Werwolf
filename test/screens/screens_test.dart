import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:werwolf/models/game_state.dart';
import 'package:werwolf/models/roles.dart';
import 'package:werwolf/theme.dart';
import 'package:werwolf/ui/room_view.dart';
import 'package:werwolf/ui/screens/home_screen.dart';
import 'package:werwolf/ui/screens/rules_screen.dart';
import 'package:werwolf/ui/widgets/atmosphere.dart';
import 'package:werwolf/ui/widgets/role_sheet.dart';
import 'package:werwolf/ui/widgets/video_tile.dart';

// Rendert Bildschirme als PNG (nur zur Design-Kontrolle):
// flutter test --update-goldens test/screens
Future<void> _fonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }

  await load('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf', 'Cinzel-Black.ttf']);
  await load('Cormorant', ['Cormorant-Regular.ttf', 'Cormorant-SemiBold.ttf', 'Cormorant-Bold.ttf', 'Cormorant-Italic.ttf', 'Cormorant-SemiBoldItalic.ttf']);
  final icons = File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

Future<void> _shot(WidgetTester t, Widget w, String name, {bool extraPump = false}) async {
  t.view.physicalSize = const Size(1080, 2280);
  t.view.devicePixelRatio = 2.75;
  await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: w));
  await t.pump(const Duration(milliseconds: 2000));
  if (extraPump) {
    await t.pump();
    await t.pump(const Duration(seconds: 1));
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
}

Widget _gameMock({required bool night}) {
  final names = ['Mara', 'Jonas', 'Ilse', 'Konrad', 'Vera', 'Theo', 'Agnes', 'Bruno'];
  return Scaffold(
    body: Atmosphere(
      bloodMoon: night,
      showMoon: night,
      darkness: night ? 0.35 : 0,
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 8),
          Text(night ? 'DIE WERWÖLFE ERWACHEN' : 'DAS GERICHT',
              style: const TextStyle(fontFamily: AppText.display, fontSize: 17, letterSpacing: 3, fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text(
              night
                  ? 'Die Werwölfe erwachen. Sie erkennen einander im Dunkeln … und wählen ihr Opfer.'
                  : 'Die Zeit des Redens ist vorbei. Zeigt mit dem Finger auf den Schuldigen.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontStyle: FontStyle.italic),
            ),
          ),
          const BloodDivider(width: 240),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: GridView.count(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 3 / 4,
                children: [
                  for (var i = 0; i < names.length; i++)
                    VideoTile(
                      name: names[i],
                      isSelf: i == 0,
                      dead: i == 5,
                      revealedRole: i == 5 ? Role.seherin : null,
                      mayor: i == 2,
                      selected: i == 3,
                      votes: night ? (i == 3 ? 2 : 0) : (i == 3 ? 3 : (i == 6 ? 1 : 0)),
                      tag: night && (i == 0 || i == 4) && i != 0 ? 'Rudel' : null,
                      showVideo: !night || i == 0 || i == 4,
                      dim: night && (i == 0 || i == 4 || i == 5),
                    ),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.night.withValues(alpha: 0.92), border: Border.all(color: AppColors.blood)),
            child: Column(children: [
              Text(night ? 'Wählt euer Opfer. Ihr seht und hört euch gegenseitig.' : 'Wen richtet das Dorf?',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 10),
              GothicButton(dense: true, icon: Icons.bloodtype, label: night ? 'Zuschlagen: Konrad' : 'Verurteilen: Konrad', onPressed: () {}),
            ]),
          ),
        ]),
      ),
    ),
  );
}

void main() {
  setUpAll(_fonts);
  SharedPreferences.setMockInitialValues({'name': 'Mara'});

  testWidgets('home', (t) => _shot(t, const HomeScreen(), 'home'));
  testWidgets('rules', (t) => _shot(t, const RulesScreen(), 'rules'));
  testWidgets('day', (t) => _shot(t, _gameMock(night: false), 'day'));
  testWidgets('night', (t) => _shot(t, _gameMock(night: true), 'night'));
  testWidgets('role', (t) async {
    final v = RoomView(
      me: 'a',
      room: RoomState('X', {'phase': Phase.night, 'hostId': 'a'}),
      players: [PlayerState('a', {'name': 'Mara'}), PlayerState('b', {'name': 'Jonas'})],
      secret: SecretState({'role': 'werwolf', 'wolves': ['a', 'b']}),
      myAction: null,
    );
    await _shot(
        t,
        Builder(builder: (c) {
          WidgetsBinding.instance.addPostFrameCallback((_) => showRoleSheet(c, v));
          return const Scaffold(body: Atmosphere(bloodMoon: true, child: SizedBox()));
        }),
        'role', extraPump: true);
  });
}
