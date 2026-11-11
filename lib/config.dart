/// ICE-Server für die Video-Verbindungen.
///
/// STUN reicht in den meisten WLANs. In Mobilfunknetzen (CGNAT) brauchen
/// Verbindungen oft einen TURN-Server. Trage hier deinen eigenen ein
/// (z. B. coturn auf einem kleinen Server oder einen Anbieter wie
/// Metered, Twilio oder Cloudflare Calls), bevor du die App veröffentlichst.
const List<Map<String, dynamic>> kIceServers = [
  {
    'urls': [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ],
  },
  // {
  //   'urls': ['turn:turn.example.com:3478?transport=udp', 'turns:turn.example.com:5349'],
  //   'username': 'werwolf',
  //   'credential': 'GEHEIM',
  // },
];

/// Mindestanzahl Spieler. Im Debug-Build reichen 3 zum Testen.
const int kMinPlayersRelease = 5;
const int kMinPlayersDebug = 3;
