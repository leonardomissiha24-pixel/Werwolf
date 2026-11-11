// PLATZHALTER – wird durch `flutterfire configure --platforms=android,windows`
// überschrieben.
//
// Anleitung: siehe README.md, Abschnitt "Firebase einrichten".
// Windows nutzt in Firebase die Konfiguration einer *Web-App*
// (Projekteinstellungen → Deine Apps → Web-App hinzufügen).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => switch (defaultTargetPlatform) {
        TargetPlatform.windows => windows,
        _ => android,
      };

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'DEIN_API_KEY',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'dein-firebase-projekt',
    storageBucket: 'dein-firebase-projekt.firebasestorage.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'DEIN_API_KEY',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'dein-firebase-projekt',
    authDomain: 'dein-firebase-projekt.firebaseapp.com',
    storageBucket: 'dein-firebase-projekt.firebasestorage.app',
  );
}
