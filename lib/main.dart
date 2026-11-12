import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'services/room_repository.dart';
import 'theme.dart';
import 'ui/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.ink,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Jedes Gerät bekommt einmalig eine zufällige Kennung (kein Konto nötig).
  final prefs = await SharedPreferences.getInstance();
  var uid = prefs.getString('uid');
  if (uid == null) {
    uid = RoomRepository.randomId();
    await prefs.setString('uid', uid);
  }
  RoomRepository.instance = RoomRepository(uid: uid);
  runApp(const WerwolfApp());
}

class WerwolfApp extends StatelessWidget {
  const WerwolfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Werwolf: Blutmond',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
