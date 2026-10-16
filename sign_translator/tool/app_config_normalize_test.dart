// Server-address parsing for Tailscale / MagicDNS / LAN inputs.
//   flutter test tool/app_config_normalize_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../lib/config/app_config.dart';

void main() {
  test('normalize accepts Tailscale, MagicDNS, LAN and URLs', () {
    const cases = {
      '100.118.113.125': '100.118.113.125:8765',
      '100.118.113.125:8765': '100.118.113.125:8765',
      ' 100.118.113.125:9000 ': '100.118.113.125:9000',
      'althd.tailad21f4.ts.net': 'althd.tailad21f4.ts.net:8765',
      'althd.tailad21f4.ts.net.': 'althd.tailad21f4.ts.net:8765',
      'althd.tailad21f4.ts.net.:8765': 'althd.tailad21f4.ts.net:8765',
      'althd': 'althd:8765',
      'ws://althd.tailad21f4.ts.net:8765/': 'althd.tailad21f4.ts.net:8765',
      'http://100.118.113.125:8765/health': '100.118.113.125:8765',
      '192.168.68.101': '192.168.68.101:8765',
      '127.0.0.1:8765': '127.0.0.1:8765',
    };
    cases.forEach((input, want) => expect(AppConfig.normalize(input), want, reason: input));
    for (final bad in ['', '   ', 'host:0', 'host:99999', ':8765', 'a b']) {
      expect(AppConfig.normalize(bad), isNull, reason: bad);
    }
  });
}
