// PLATZHALTER – wird durch `flutterfire configure` überschrieben.
//
// Anleitung: siehe README.md, Abschnitt "Firebase einrichten".
// Alternativ die Werte aus der Firebase-Konsole
// (Projekteinstellungen → Deine Apps → Android-App) hier eintragen.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'DEIN_API_KEY',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'dein-firebase-projekt',
    storageBucket: 'dein-firebase-projekt.firebasestorage.app',
  );
}
