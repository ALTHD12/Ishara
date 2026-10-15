import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';

/// Small pill showing backend link state. Tap to retry now, long-press to
/// edit the server address.
class ConnectionStatusBadge extends StatelessWidget {
  const ConnectionStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SignClassifierService>(
      builder: (context, svc, _) {
        final (color, label) = switch (svc.status) {
          ConnectionStatus.connected => (const Color(0xFF2ECC71), 'ONLINE'),
          ConnectionStatus.connecting => (const Color(0xFFF5A623), 'CONNECTING'),
          ConnectionStatus.reconnecting => (const Color(0xFFF5A623), 'RECONNECTING'),
          ConnectionStatus.paused => (Colors.grey, 'PAUSED'),
          ConnectionStatus.disconnected => (const Color(0xFFFF3B5C), 'OFFLINE'),
        };
        final ping = svc.lastPingRtt;
        final detail = svc.status == ConnectionStatus.connected && ping != null
            ? ' ${ping.inMilliseconds}ms'
            : '';
        return GestureDetector(
          onTap: svc.reconnectNow,
          onLongPress: () => showServerSettingsDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  '$label$detail',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dialog to edit the backend `host:port`. Saved with shared_preferences.
Future<void> showServerSettingsDialog(BuildContext context) async {
  final svc = context.read<SignClassifierService>();
  final controller = TextEditingController(text: svc.serverAddress);
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('BACKEND SERVER'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Laptop IP[:port]',
                hintText: '192.168.43.20:8765',
                errorText: error,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use the ws:// address printed by the backend at startup.\n'
              '127.0.0.1:8765 = USB cable (adb reverse).',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => controller.text = '127.0.0.1:8765',
            child: const Text('USB DEFAULT'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await svc.setServer(controller.text);
                if (ctx.mounted) Navigator.pop(ctx);
              } on FormatException catch (e) {
                setState(() => error = e.message);
              }
            },
            child: const Text('SAVE & CONNECT'),
          ),
        ],
      ),
    ),
  );
}
