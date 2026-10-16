import 'dart:collection';

/// Rolling link statistics for the live debug readout (Problem C):
/// RTT p50/p95, effective result rate, uplink bytes/s, frames skipped while
/// waiting for the network and results that never came back.
class NetStats {
  static const double _windowMs = 3000;

  final ListQueue<(double, double, int)> _samples = ListQueue(); // (tRecvMs, rttMs, bytes)

  /// Camera frames skipped because the previous frame was still in flight.
  int busyDrops = 0;
  /// Results given up on after LiveConfig.resultTimeout.
  int timeouts = 0;

  void onResult(double tRecvMs, double rttMs, int bytes) {
    _samples.add((tRecvMs, rttMs, bytes));
    while (_samples.isNotEmpty && _samples.first.$1 < tRecvMs - _windowMs) {
      _samples.removeFirst();
    }
  }

  void reset() {
    _samples.clear();
    busyDrops = 0;
    timeouts = 0;
  }

  double _pct(double q) {
    if (_samples.isEmpty) return double.nan;
    final v = [for (final s in _samples) s.$2]..sort();
    return v[((v.length - 1) * q).round()];
  }

  double get rttP50 => _pct(0.5);
  double get rttP95 => _pct(0.95);

  double get _spanS {
    if (_samples.length < 2) return double.nan;
    return (_samples.last.$1 - _samples.first.$1) / 1000.0;
  }

  /// Results per second = frames actually processed per second.
  double get fps => _samples.length < 2 ? 0 : (_samples.length - 1) / _spanS;

  /// Uplink payload, kB/s.
  double get kBps {
    if (_samples.length < 2) return 0;
    var b = 0;
    for (final s in _samples.skip(1)) {
      b += s.$3;
    }
    return b / 1024.0 / _spanS;
  }

  String summary() =>
      'RTT ${rttP50.toStringAsFixed(0)}/${rttP95.toStringAsFixed(0)}ms  '
      '${fps.toStringAsFixed(1)}fps  ${kBps.toStringAsFixed(0)}kB/s  '
      'skip $busyDrops  lost $timeouts';
}
