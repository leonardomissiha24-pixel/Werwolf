import 'package:flutter_tts/flutter_tts.dart';

/// Düstere Erzählerstimme (Text-to-Speech, Deutsch).
class Narrator {
  final FlutterTts _tts = FlutterTts();
  bool enabled = true;
  bool _ready = false;

  Future<void> init() async {
    try {
      await _tts.setLanguage('de-DE');
      await _tts.setPitch(0.62);
      await _tts.setSpeechRate(0.40);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> say(String text) async {
    if (!enabled || !_ready || text.isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
