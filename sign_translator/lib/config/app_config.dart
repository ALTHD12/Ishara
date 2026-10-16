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

  /// `host:port` (no scheme, no path).
  static String get server => _server;

  /// WebSocket endpoint. The backend serves it at the bare root path "/".
  static String get backendWsUrl => 'ws://$_server/';
  static String get backendHttpUrl => 'http://$_server';

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _server = normalize(prefs.getString(_prefsKey) ?? defaultServer) ?? defaultServer;
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

  /// Accepts `1.2.3.4`, `1.2.3.4:8765`, `ws://1.2.3.4:8765/`, `http://host:8765`.
  /// Returns `host:port`, or null if unusable.
  static String? normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^(wss?|https?)://', caseSensitive: false), '');
    final slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    if (s.isEmpty || s.contains(' ')) return null;
    final colon = s.lastIndexOf(':');
    if (colon < 0) return '$s:8765';
    final port = int.tryParse(s.substring(colon + 1));
    if (port == null || port <= 0 || port > 65535 || colon == 0) return null;
    return s;
  }
}
