# Werwolf: Blutmond

Online-Werwolf für Android mit Live-Video: Jeder spielt auf dem eigenen Handy,
alle sehen und hören sich über die Kamera. Nachts erlöschen die Bilder – nur die
Werwölfe sehen und hören einander. Eine düstere Erzählerstimme führt durch die Nacht.

**Plattformen:** Android (Play Store) und Windows 10/11 (Installer).

**Technik:** Flutter · WebRTC (direkte Video-Verbindungen zwischen allen Spielern, 5–12 Spieler) ·
öffentliche MQTT-Vermittlungsserver zum Finden der Geräte – **kein Konto, kein eigener Server, keine Einrichtung nötig.**

## Wie sich die Geräte finden
Das Gerät des Spielleiters hält den Spielzustand und verteilt ihn über einen öffentlichen
Vermittlungsserver (Liste in `lib/config.dart`, die App probiert sie der Reihe nach durch).
Alles wird vorher auf dem Gerät verschlüsselt (AES-256-GCM, Schlüssel aus dem Dorfcode);
Rollen und Nachtaktionen zusätzlich mit einem Schlüssel, den nur Spielleiter und der jeweilige
Spieler kennen (X25519). Bild und Ton laufen nie über diese Server, sondern direkt von Gerät zu Gerät.

Grenzen: Die öffentlichen Server sind kostenlose Gemeinschaftsdienste ohne Ausfallgarantie.
Für eine große Nutzerzahl im Play Store sollte in `lib/config.dart` ein eigener MQTT-Server
(z. B. Mosquitto auf einem kleinen Server) eingetragen werden.

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

### 2. TURN-Server (wichtig für Mobilfunk)
Im WLAN reichen die eingetragenen STUN-Server. Im Mobilfunknetz scheitern direkte
Verbindungen oft – dann braucht es einen TURN-Server. Trage ihn in `lib/config.dart` ein
(eigener [coturn](https://github.com/coturn/coturn) oder z. B. Metered / Cloudflare Calls / Twilio).

### 3. App-ID festlegen
Die Paketkennung ist `de.blutmond.werwolf` (in `android/app/build.gradle.kts`).
Ändere sie **vor** dem ersten Upload, falls du eine eigene willst – danach ist sie fest.

### 4. Signaturschlüssel erzeugen
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

### 5. Bauen
```bash
flutter pub get
flutter test
flutter build appbundle --release
```
Ergebnis: `build/app/outputs/bundle/release/app-release.aab`

### 6. Google Play Console
1. Entwicklerkonto (einmalig 25 $) auf <https://play.google.com/console>.
2. App erstellen → AAB hochladen (zuerst „Interner Test“).
3. Store-Eintrag: Icon `store/icon_512.png`, Feature-Grafik `store/feature_graphic_1024x500.png`,
   mind. 2 Screenshots vom echten Spiel.
4. **Datenschutzerklärung:** `docs/datenschutz.html` ausfüllen ([PLATZHALTER]) und öffentlich hosten
   (z. B. GitHub Pages), URL eintragen.
5. **Datensicherheit:** Erhoben werden *Fotos/Videos & Audio* (nur übertragen, nicht gespeichert,
   verschlüsselt), *Name* (Spielername); keine Weitergabe, keine Werbung.
6. Inhaltsbewertung: Fantasy-Gewalt; die App hat **Live-Kommunikation zwischen Nutzern** → angeben.
7. **Neue Privatkonten:** Google verlangt vor dem Produktions-Release einen geschlossenen Test mit
   mind. 12 Testern über 14 Tage.

---

## Windows-Installer

Der Installer wird automatisch von GitHub Actions gebaut (`.github/workflows/windows.yml`):

- **Direkter Download der neuesten Version:**
  <https://github.com/leonardomissiha24-pixel/Werwolf/releases/latest/download/Werwolf-Blutmond-Setup.exe>
- Jeder Push auf `main` baut den Installer neu und legt ihn ins Release `v<version>` (Version aus `pubspec.yaml`).
  Für eine neue Version einfach `version:` in `pubspec.yaml` erhöhen.

Hinweise:
- Der Installer ist nicht signiert, deshalb warnt SmartScreen beim ersten Start
  („Weitere Informationen“ → „Trotzdem ausführen“). Für eine Signatur braucht man ein Code-Signing-Zertifikat.
- Kamera am PC: *Einstellungen → Datenschutz & Sicherheit → Kamera → „Desktop-Apps Zugriff erlauben“* muss an sein.
- Lokal bauen (auf Windows mit Visual Studio 2022 + „Desktopentwicklung mit C++“):
  `flutter build windows --release`, dann `installer\werwolf.iss` mit Inno Setup 6 kompilieren.

---

## Projektstruktur
```
lib/
  main.dart                    Start
  config.dart                  Vermittlungsserver, STUN/TURN-Server, Mindestspielerzahl
  theme.dart                   Farben & Schriften (Cinzel, Cormorant Garamond)
  models/roles.dart            Rollen, Nachtschritte, Phasen, Sieg-Texte
  models/game_state.dart       Datenmodelle (Raum, Spieler, Geheimnisse)
  services/game_engine.dart    Spielleiter-Logik (läuft beim Gastgeber)
  services/video_mesh.dart     WebRTC-Netz + Sichtbarkeitsregeln
  services/room_repository.dart  Dorf gründen/beitreten, Verteilung des Spielzustands
  net/                         Transport (MQTT), Verschlüsselung, Spielzustand des Spielleiters
  services/narrator.dart       Erzählerstimme (Text-to-Speech)
  ui/screens/                  Start, Spielraum, Regeln
  ui/widgets/                  Nebel/Mond, Videokacheln, Rollenkarte
test/engine_test.dart          simuliert >80 komplette Partien mit Bots
test/network_test.dart         ganze Partien über die Netzwerkschicht inkl. Lauschangriff
windows/                       Windows-Runner (Fenster, Icon)
installer/werwolf.iss          Inno-Setup-Skript für den Installer
.github/workflows/windows.yml  baut den Windows-Installer automatisch
```

## Bekannte Grenzen
- Der Gastgeber ist der Spielleiter: Schließt er die App, endet das Spiel für alle.
- Spielleiter-Logik läuft auf dem Gerät des Gastgebers; ein manipulierter Client des Gastgebers könnte Rollen auslesen (für ein Partyspiel unter Freunden üblich).
- Wer den Dorfcode kennt, kann den öffentlichen Spielstand mitlesen (nicht aber Rollen und Nachtaktionen).
- Vollvermaschtes Video: Ab ~10 Spielern steigt die Last auf älteren Handys spürbar (Auflösung ist deshalb auf 480×360 @ 15 fps begrenzt).
