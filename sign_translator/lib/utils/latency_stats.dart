import 'package:flutter/foundation.dart';

/// Rolling per-stage latency stats for the live pipeline.
///
/// Enable with `flutter run --dart-define=ISL_DEBUG_TIMING=true`.
/// Prints p50/p95 per stage every [summaryEvery] frames.
class LatencyStats {
  static const bool enabled =
      bool.fromEnvironment('ISL_DEBUG_TIMING', defaultValue: false);

  final String tag;
  final int summaryEvery;
  final Map<String, List<double>> _samples = {};
  int _count = 0;

  LatencyStats(this.tag, {this.summaryEvery = 60});

  void record(Map<String, double> stages) {
    if (!enabled) return;
    stages.forEach((k, v) => (_samples[k] ??= []).add(v));
    _count++;
    if (_count % summaryEvery == 0) _printSummary();
  }

  void _printSummary() {
    final parts = <String>[];
    _samples.forEach((k, vals) {
      if (vals.isEmpty) return;
      vals.sort();
      final p50 = vals[vals.length ~/ 2];
      final p95 = vals[((vals.length - 1) * 0.95).round()];
      parts.add('$k=${p50.toStringAsFixed(1)}/${p95.toStringAsFixed(1)}');
    });
    debugPrint('[TIMING $tag] n=$_count (p50/p95 ms) ${parts.join(' ')}');
    _samples.clear();
  }
}
