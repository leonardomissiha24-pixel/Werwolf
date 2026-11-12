import 'dart:async';

/// Eine empfangene Nachricht.
typedef NetMessage = ({String topic, String payload});

/// Minimaler Publish/Subscribe-Kanal (MQTT-Semantik mit "retained"-Nachrichten).
abstract class Transport {
  Future<void> connect();
  Future<void> disconnect();
  bool get connected;

  /// [filter] darf als letztes Segment `+` enthalten.
  void subscribe(String filter);
  void publish(String topic, String payload, {bool retain = false});

  /// Alle eingehenden Nachrichten.
  Stream<NetMessage> get messages;

  /// Feuert nach einem automatischen Wiederverbinden.
  Stream<void> get reconnected;
}

bool topicMatches(String filter, String topic) {
  final f = filter.split('/'), t = topic.split('/');
  if (f.length != t.length) return false;
  for (var i = 0; i < f.length; i++) {
    if (f[i] != '+' && f[i] != t[i]) return false;
  }
  return true;
}

/// Vermittler im Arbeitsspeicher – für Tests.
class MemoryHub {
  final Map<String, String> _retained = {};
  final List<MemoryTransport> _clients = [];

  void _publish(String topic, String payload, bool retain) {
    if (retain) {
      if (payload.isEmpty) {
        _retained.remove(topic);
      } else {
        _retained[topic] = payload;
      }
    }
    for (final c in [..._clients]) {
      c._deliver(topic, payload);
    }
  }
}

class MemoryTransport implements Transport {
  MemoryTransport(this.hub);
  final MemoryHub hub;
  final _ctrl = StreamController<NetMessage>.broadcast();
  final _filters = <String>{};
  bool _connected = false;

  @override
  bool get connected => _connected;

  @override
  Future<void> connect() async {
    _connected = true;
    hub._clients.add(this);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    hub._clients.remove(this);
  }

  void _deliver(String topic, String payload) {
    if (!_connected || payload.isEmpty) return;
    if (_filters.any((f) => topicMatches(f, topic))) {
      scheduleMicrotask(() {
        if (!_ctrl.isClosed) _ctrl.add((topic: topic, payload: payload));
      });
    }
  }

  @override
  void subscribe(String filter) {
    if (!_filters.add(filter)) return;
    hub._retained.forEach((t, p) {
      if (topicMatches(filter, t)) {
        scheduleMicrotask(() {
          if (!_ctrl.isClosed) _ctrl.add((topic: t, payload: p));
        });
      }
    });
  }

  @override
  void publish(String topic, String payload, {bool retain = false}) {
    if (_connected) hub._publish(topic, payload, retain);
  }

  @override
  Stream<NetMessage> get messages => _ctrl.stream;

  @override
  Stream<void> get reconnected => const Stream.empty();
}
