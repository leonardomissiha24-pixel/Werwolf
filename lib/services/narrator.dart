import 'package:flutter_tts/flutter_tts.dart';

/// Düstere Erzählerstimme (Text-to-Speech, Deutsch).
class Narrator {
  final FlutterTts _tts = FlutterTts();
  bool enabled = true;
  bool _ready = false;

  Future<void> init() async {
    // Einzeln absichern: Unter Windows fehlt evtl. eine deutsche Stimme
    // oder eine Einstellung wird nicht unterstützt – vorlesen soll trotzdem gehen.
    Future<void> attempt(Future<dynamic> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    await attempt(() => _tts.setLanguage('de-DE'));
    await attempt(() => _tts.setPitch(0.62));
    await attempt(() => _tts.setSpeechRate(0.40));
    await attempt(() => _tts.setVolume(1.0));
    _ready = true;
  }

  Future<void> say(String text) async {
    if (!enabled || !_ready || text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
