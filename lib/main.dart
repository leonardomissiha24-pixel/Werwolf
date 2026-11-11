import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'firebase_options.dart';
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

  String? initError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await RoomRepository.instance.ensureSignedIn();
  } catch (e) {
    initError = '$e';
  }
  runApp(WerwolfApp(initError: initError));
}

class WerwolfApp extends StatelessWidget {
  const WerwolfApp({super.key, this.initError});
  final String? initError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Werwolf: Blutmond',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: HomeScreen(initError: initError),
    );
  }
}
