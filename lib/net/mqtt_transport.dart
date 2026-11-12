import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'transport.dart';

/// Ein öffentlich erreichbarer Vermittlungsserver.
class Broker {
  const Broker(this.host, {this.tlsPort = 8883, this.plainPort = 1883});
  final String host;
  final int tlsPort;
  final int plainPort;
}

/// Transport über einen MQTT-Vermittlungsserver. Versucht zuerst TLS, dann
/// unverschlüsseltes TCP – die Nutzdaten sind ohnehin Ende-zu-Ende-verschlüsselt.
class MqttTransport implements Transport {
  MqttTransport(this.broker, {this.allowPlain = true});

  final Broker broker;
  final bool allowPlain;
  MqttServerClient? _client;
  final _ctrl = StreamController<NetMessage>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  final _filters = <String>{};
  StreamSubscription? _sub;

  @override
  bool get connected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  MqttServerClient _make(bool secure) {
    final id = 'ww${Random.secure().nextInt(1 << 32).toRadixString(36)}${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final c = MqttServerClient.withPort(broker.host, id, secure ? broker.tlsPort : broker.plainPort)
      ..secure = secure
      ..logging(on: false)
      ..setProtocolV311()
      ..keepAlivePeriod = 20
      ..connectTimeoutPeriod = 6000
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true;
    c.connectionMessage = MqttConnectMessage().withClientIdentifier(id).startClean();
    c.onAutoReconnected = () {
      if (!_reconnected.isClosed) _reconnected.add(null);
    };
    return c;
  }

  @override
  Future<void> connect() async {
    Object? lastError;
    for (final secure in [true, if (allowPlain) false]) {
      final c = _make(secure);
      try {
        await c.connect().timeout(const Duration(seconds: 8));
        if (c.connectionStatus?.state == MqttConnectionState.connected) {
          _client = c;
          _sub = c.updates?.listen(_onUpdates);
          for (final f in _filters) {
            c.subscribe(f, MqttQos.atLeastOnce);
          }
          return;
        }
      } catch (e) {
        lastError = e;
        debugPrint('MQTT ${broker.host} (tls=$secure): $e');
      }
      try {
        c.autoReconnect = false;
        c.disconnect();
      } catch (_) {}
    }
    throw StateError('Vermittlungsserver ${broker.host} nicht erreichbar: $lastError');
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> list) {
    for (final m in list) {
      final msg = m.payload;
      if (msg is! MqttPublishMessage) continue;
      final bytes = msg.payload.message;
      if (bytes.isEmpty) continue;
      _ctrl.add((topic: m.topic, payload: utf8.decode(bytes, allowMalformed: true)));
    }
  }

  @override
  void subscribe(String filter) {
    if (!_filters.add(filter)) return;
    if (connected) _client!.subscribe(filter, MqttQos.atLeastOnce);
  }

  @override
  void publish(String topic, String payload, {bool retain = false}) {
    final c = _client;
    if (c == null) return;
    try {
      final b = MqttClientPayloadBuilder()..addString(payload);
      c.publishMessage(topic, MqttQos.atLeastOnce, b.payload!, retain: retain);
    } catch (e) {
      debugPrint('MQTT publish: $e');
    }
  }

  @override
  Stream<NetMessage> get messages => _ctrl.stream;

  @override
  Stream<void> get reconnected => _reconnected.stream;

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    final c = _client;
    _client = null;
    if (c != null) {
      try {
        c.autoReconnect = false;
        c.disconnect();
      } catch (_) {}
    }
  }
}
