# Werwolf: Blutmond

Online-Werwolf für Android mit Live-Video: Jeder spielt auf dem eigenen Handy,
alle sehen und hören sich über die Kamera. Nachts erlöschen die Bilder – nur die
Werwölfe sehen und hören einander. Eine düstere Erzählerstimme führt durch die Nacht.

**Technik:** Flutter · Firebase (anonyme Anmeldung + Cloud Firestore) · WebRTC (direkte Video-Verbindungen zwischen allen Spielern, 5–12 Spieler)

## Rollen
Werwolf · Weißer Werwolf · Dorfbewohner · Seherin · Hexe · Jäger · Amor · Beschützer ·
Kleines Mädchen (sieht nachts verschwommen die Kameras der Wölfe) · Dorfältester · Dorfdepp ·
dazu Bürgermeisterwahl (Stimme zählt doppelt) und Geister (Tote sehen alle Rollen, bleiben stumm).

## Wie die Kamera eingebunden ist
| Phase | Wer sieht / hört wen |
|---|---|
| Lobby, Tag, Abstimmung | Alle sehen und hören alle. Tote: nur Bild (grau), kein Ton. |
| Nacht | Alle Kameras aus, Bildschirm schwarz („Du schläfst“). |
| Werwolf-Phase | Wölfe sehen + hören sich gegenseitig. Das Mädchen sieht ihre Bilder verschwommen und ohne Namen. Geister sehen zu. |

Die Freigabe wird auf **Senderseite** gesteuert (`replaceTrack`): Ein Bild, das nicht gesehen werden darf, wird gar nicht erst verschickt.

---

## Veröffentlichen – Schritt für Schritt

### 1. Werkzeuge
- [Flutter](https://docs.flutter.dev/get-started/install) (stabil, ≥ 3.50) und Android Studio bzw. Android SDK (Plattform 37)
- `npm install -g firebase-tools` und `dart pub global activate flutterfire_cli`

### 2. Firebase einrichten (kostenloser Spark-Tarif reicht)
1. Projekt anlegen auf <https://console.firebase.google.com>.
2. **Authentication → Anmeldemethode → Anonym** aktivieren.
3. **Firestore Database → Datenbank erstellen** (Standort `europe-west3` Frankfurt).
4. Im Projektordner:
   ```bash
   firebase login
   flutterfire configure --platforms=android --android-package-name=de.blutmond.werwolf
   firebase use --add          # dein Projekt wählen
   firebase deploy --only firestore:rules
   ```
   `flutterfire configure` überschreibt `lib/firebase_options.dart` mit deinen echten Werten.
5. Optional, aber empfohlen: **Firestore → TTL-Richtlinien** für das Feld `expiresAt` in den
   Sammlungsgruppen `rooms`, `players`, `secrets`, `actions` anlegen → alte Spiele löschen sich nach 24 h.

### 3. TURN-Server (wichtig für Mobilfunk)
Im WLAN reichen die eingetragenen STUN-Server. Im Mobilfunknetz scheitern direkte
Verbindungen oft – dann braucht es einen TURN-Server. Trage ihn in `lib/config.dart` ein
(eigener [coturn](https://github.com/coturn/coturn) oder z. B. Metered / Cloudflare Calls / Twilio).

### 4. App-ID festlegen
Die Paketkennung ist `de.blutmond.werwolf` (in `android/app/build.gradle.kts`).
Ändere sie **vor** dem ersten Upload, falls du eine eigene willst – danach ist sie fest.

### 5. Signaturschlüssel erzeugen
```bash
keytool -genkey -v -keystore ~/werwolf-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Dann `android/key.properties` anlegen (wird nicht eingecheckt):
```
storePassword=DEIN_PASSWORT
keyPassword=DEIN_PASSWORT
keyAlias=upload
storeFile=/pfad/zu/werwolf-upload.jks
```
Schlüssel und Passwort sicher aufbewahren!

### 6. Bauen
```bash
flutter pub get
flutter test
flutter build appbundle --release
```
Ergebnis: `build/app/outputs/bundle/release/app-release.aab`

### 7. Google Play Console
1. Entwicklerkonto (einmalig 25 $) auf <https://play.google.com/console>.
2. App erstellen → AAB hochladen (zuerst „Interner Test“).
3. Store-Eintrag: Icon `store/icon_512.png`, Feature-Grafik `store/feature_graphic_1024x500.png`,
   mind. 2 Screenshots vom echten Spiel.
4. **Datenschutzerklärung:** `docs/datenschutz.html` ausfüllen ([PLATZHALTER]) und öffentlich hosten
   (z. B. GitHub Pages), URL eintragen.
5. **Datensicherheit:** Erhoben werden *Fotos/Videos & Audio* (nur übertragen, nicht gespeichert,
   verschlüsselt), *Name* (Spielername) und *App-Interaktionen*; keine Weitergabe, keine Werbung.
6. Inhaltsbewertung: Fantasy-Gewalt; die App hat **Live-Kommunikation zwischen Nutzern** → angeben.
7. **Neue Privatkonten:** Google verlangt vor dem Produktions-Release einen geschlossenen Test mit
   mind. 12 Testern über 14 Tage.

---

## Projektstruktur
```
lib/
  main.dart                    Start, Firebase-Init
  config.dart                  STUN/TURN-Server, Mindestspielerzahl
  theme.dart                   Farben & Schriften (Cinzel, Cormorant Garamond)
  models/roles.dart            Rollen, Nachtschritte, Phasen, Sieg-Texte
  models/game_state.dart       Firestore-Datenmodelle
  services/game_engine.dart    Spielleiter-Logik (läuft beim Gastgeber)
  services/video_mesh.dart     WebRTC-Netz + Sichtbarkeitsregeln
  services/room_repository.dart  Räume beitreten/erstellen, Aktionen
  services/narrator.dart       Erzählerstimme (Text-to-Speech)
  ui/screens/                  Start, Spielraum, Regeln
  ui/widgets/                  Nebel/Mond, Videokacheln, Rollenkarte
test/engine_test.dart          simuliert >80 komplette Partien mit Bots
firestore.rules                Sicherheitsregeln
```

## Bekannte Grenzen
- Der Gastgeber ist der Spielleiter: Schließt er die App, endet das Spiel für alle.
- Spielleiter-Logik läuft auf dem Gerät des Gastgebers; ein manipulierter Client des Gastgebers könnte Rollen auslesen (für ein Partyspiel unter Freunden üblich; für öffentliche Lobbys wäre eine Cloud Function als Spielleiter nötig).
- Vollvermaschtes Video: Ab ~10 Spielern steigt die Last auf älteren Handys spürbar (Auflösung ist deshalb auf 480×360 @ 15 fps begrenzt).
