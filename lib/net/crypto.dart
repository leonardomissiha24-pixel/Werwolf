import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Ende-zu-Ende-Verschlüsselung der Spieldaten (AES-256-GCM, X25519).
class Crypto {
  static final _aes = AesGcm.with256bits();
  static final _x = X25519();

  /// Schlüssel und Kanalname, die sich aus dem Dorfcode ergeben.
  static Future<({SecretKey key, String channel})> forRoom(String code) async {
    final k = await Sha256().hash(utf8.encode('werwolf-blutmond/key/$code'));
    final c = await Sha256().hash(utf8.encode('werwolf-blutmond/channel/$code'));
    final hex = c.bytes.take(10).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return (key: SecretKey(k.bytes), channel: 'wwbm1/$hex');
  }

  static Future<SimpleKeyPair> newKeyPair() => _x.newKeyPair();

  static Future<String> publicKeyOf(SimpleKeyPair pair) async =>
      base64Encode((await pair.extractPublicKey()).bytes);

  /// Gemeinsamer Schlüssel zwischen mir und dem Besitzer von [otherPublic].
  static Future<SecretKey> shared(SimpleKeyPair mine, String otherPublic) async {
    final s = await _x.sharedSecretKey(
      keyPair: mine,
      remotePublicKey: SimplePublicKey(base64Decode(otherPublic), type: KeyPairType.x25519),
    );
    final h = await Sha256().hash(await s.extractBytes());
    return SecretKey(h.bytes);
  }

  /// [json] wird sofort (synchron) serialisiert, spätere Änderungen wirken nicht mehr.
  static Future<String> seal(SecretKey key, Object json) {
    final clear = utf8.encode(jsonEncode(json));
    return _seal(key, clear);
  }

  static Future<String> _seal(SecretKey key, List<int> clear) async {
    final box = await _aes.encrypt(clear, secretKey: key);
    return base64Encode(box.concatenation());
  }

  /// Liefert `null`, wenn die Nachricht nicht mit [key] verschlüsselt wurde.
  static Future<Map<String, dynamic>?> open(SecretKey key, String payload) async {
    try {
      final box = SecretBox.fromConcatenation(base64Decode(payload), nonceLength: 12, macLength: 16);
      final clear = await _aes.decrypt(box, secretKey: key);
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
    } catch (_) {
      return null;
    }
  }
}
