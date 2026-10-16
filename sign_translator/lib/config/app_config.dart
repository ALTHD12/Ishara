import 'package:shared_preferences/shared_preferences.dart';

/// Backend address, editable at runtime from the Settings drawer and
/// persisted with shared_preferences.
///
/// Default `127.0.0.1:8765` works over the USB `adb reverse` tunnel. For
/// cable-free use, set it to the laptop's LAN / hotspot IP, e.g. `192.168.43.20:8765`.
class AppConfig {
  static const String defaultServer = '127.0.0.1:8765';
  static const String _prefsKey = 'server_address';

  static String _server = defaultServer;

  /// Live debug readout (decision reason, RTT/fps/bytes, overlay age) on the
  /// ISL->English screen. Settings > DEBUG READOUT, persisted; default from
  /// `--dart-define=ISL_DEBUG_LIVE=true`.
  static const String _debugKey = 'debug_readout';
  static bool debugReadout = const bool.fromEnvironment('ISL_DEBUG_LIVE');

  /// Overlay face detail: true = full 478-point mesh (server sends it
  /// quantized), false = light (27 contour points). Settings > FACE MESH.
  static const String _faceMeshKey = 'face_mesh_full';
  static bool faceMeshFull = true;

  static Future<void> setFaceMeshFull(bool v) async {
    faceMeshFull = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_faceMeshKey, v);
    } catch (_) {}
  }

  static Future<void> setDebugReadout(bool v) async {
    debugReadout = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_debugKey, v);
    } catch (_) {}
  }

  /// `host:port` (no scheme, no path).
  static String get server => _server;

  /// WebSocket endpoint. The backend serves it at the bare root path "/".
  static String get backendWsUrl => 'ws://$_server/';
  static String get backendHttpUrl => 'http://$_server';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _server = normalize(prefs.getString(_prefsKey) ?? defaultServer) ?? defaultServer;
      debugReadout = prefs.getBool(_debugKey) ?? debugReadout;
      faceMeshFull = prefs.getBool(_faceMeshKey) ?? faceMeshFull;
    } catch (_) {
      _server = defaultServer;
    }
  }

  static Future<void> setServer(String value) async {
    final v = normalize(value);
    if (v == null) throw const FormatException('Enter host or host:port');
    _server = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, v);
  }

  /// Accepts `1.2.3.4`, `1.2.3.4:8765`, `ws://1.2.3.4:8765/`, `http://host:8765`,
  /// Tailscale `100.x.y.z[:port]` and MagicDNS `laptop.tailXXXX.ts.net[.][:port]`.
  /// Returns `host:port`, or null if unusable.
  static String? normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^(wss?|https?)://', caseSensitive: false), '');
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    if (s.isEmpty || s.contains(' ')) return null;
    final colon = s.lastIndexOf(':');
    // MagicDNS names are often copied with a trailing dot ("x.ts.net.").
    String host(String h) => h.endsWith('.') ? h.substring(0, h.length - 1) : h;
    if (colon < 0) return s == '.' ? null : '${host(s)}:8765';
    final port = int.tryParse(s.substring(colon + 1));
    if (port == null || port <= 0 || port > 65535 || colon == 0) return null;
    return '${host(s.substring(0, colon))}:$port';
  }
}
