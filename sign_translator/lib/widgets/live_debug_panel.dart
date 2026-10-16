import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/live_config.dart';
import '../services/sign_classifier_service.dart';
import 'landmark_overlay.dart';

/// Debug readout for the live screen, shown when Settings > DEBUG READOUT is on
/// (or the app was built with --dart-define=ISL_DEBUG_LIVE=true).
///
///   why     server's reason the last frame produced no word (window not full,
///           few_active n/30, below_conf, vote_not_reached, cooldown, emit #id)
///           - needs the backend started with ISL_DEBUG_DECISIONS=1
///   client  last client-side drop (duplicate event id, not translating)
///   net     RTT p50/p95, results/s, uplink kB/s, frames skipped while waiting,
///           results lost (timeout)
///   overlay landmark age when received (+ <=16 ms to draw) and update rate
///   draw    overlay paint() cost and whole-frame raster time, p50/p95 ms
class LiveDebugPanel extends StatelessWidget {
  const LiveDebugPanel({super.key, required this.translating});
  final bool translating;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.debugReadout) return const SizedBox.shrink();
    return Consumer<SignClassifierService>(builder: (context, s, _) {
      final why = s.decisionWhy.isEmpty ? '- (backend ISL_DEBUG_DECISIONS=1 for reasons)' : s.decisionWhy;
      final sign = s.currentSign == null
          ? '-'
          : '${s.currentSign} ${(s.currentConfidence * 100).toStringAsFixed(0)}%';
      final lines = [
        'why: $why',
        'client: ${translating ? (s.clientDrop.isEmpty ? 'ok' : s.clientDrop) : 'NOT TRANSLATING (words ignored)'}',
        'net: ${s.net.summary()}  cap ${LiveConfig.maxSendFps.toStringAsFixed(0)}fps',
        'overlay: age ${s.resultAgeMs.toStringAsFixed(0)}ms @ ${s.net.fps.toStringAsFixed(1)}Hz   badge: $sign',
        'draw: ${OverlayPerf.summary()}',
      ];
      return IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          color: Colors.black.withValues(alpha: 0.65),
          child: Text(
            lines.join('\n'),
            style: const TextStyle(
              color: Color(0xFF7CFC9A),
              fontSize: 10,
              fontFamily: 'monospace',
              height: 1.25,
            ),
          ),
        ),
      );
    });
  }
}
