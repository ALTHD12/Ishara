import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../utils/camera_utils.dart';

/// Background isolate that owns the WebSocket.
///
/// Everything expensive per frame runs here, off the UI thread: YUV/BGRA→RGB
/// conversion/packing (unchanged CameraUtils math), framing, WebSocket
/// masking/sending (~25 ms for a 230 KB frame on the UI thread before), and
/// JSON decoding of results.
class FrameLink {
  Isolate? _isolate;
  SendPort? _toWorker;
  final _ready = Completer<void>();
  final _events = StreamController<List<Object?>>.broadcast();

  /// Events: ['open'], ['closed', String reason], ['msg', Map data, double rttMs,
  /// double convertMs, double sendMs, double parseMs].
  Stream<List<Object?>> get events => _events.stream;

  Future<void> start() async {
    if (_isolate != null) return _ready.future;
    final fromWorker = ReceivePort();
    _isolate = await Isolate.spawn(_workerMain, fromWorker.sendPort,
        debugName: 'frame_link');
    fromWorker.listen((m) {
      if (m is SendPort) {
        _toWorker = m;
        if (!_ready.isCompleted) _ready.complete();
      } else if (m is List) {
        _events.add(m.cast<Object?>());
      }
    });
    return _ready.future;
  }

  void connect(String url) => _toWorker?.send(['connect', url]);
  void close() => _toWorker?.send(['close']);
  void sendText(String s) => _toWorker?.send(['text', s]);

  /// [planes] are copied once into transferable buffers (no further copies).
  void sendFrame({
    required String format,
    required int width,
    required int height,
    required List<Uint8List> planes,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int rotation,
    required int captureUs,
  }) {
    _toWorker?.send([
      'frame',
      format,
      width,
      height,
      [for (final p in planes) TransferableTypedData.fromList([p])],
      yRowStride,
      uvRowStride,
      uvPixelStride,
      rotation,
      captureUs,
    ]);
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _events.close();
  }
}

/// Optional header extension understood by the backend: rotation field flag
/// meaning "8-byte big-endian capture timestamp (µs) follows the header".
const int _hdrFlagTimestamp = 0x10000;
/// Payload is packed YUV420 (see YuvPacker) instead of RGB.
const int _hdrFlagYuv420 = 0x40000;

void _workerMain(SendPort toMain) {
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  final clock = Stopwatch()..start();
  WebSocket? ws;
  int connGen = 0;
  double tSentMs = 0, convertMs = 0, sendMs = 0;

  double now() => clock.elapsedMicroseconds / 1000.0;

  inbox.listen((m) async {
    final msg = m as List;
    switch (msg[0]) {
      case 'connect':
        final gen = ++connGen;
        try {
          await ws?.close();
        } catch (_) {}
        ws = null;
        try {
          final s = await WebSocket.connect(msg[1] as String)
              .timeout(const Duration(seconds: 4));
          if (gen != connGen) {
            s.close();
            return;
          }
          s.listen(
            (data) {
              if (gen != connGen || data is! String) return;
              final tRecv = now();
              Object? decoded;
              try {
                decoded = jsonDecode(data);
              } catch (_) {
                decoded = const <String, dynamic>{};
              }
              final parseMs = now() - tRecv;
              final isPong = decoded is Map && decoded.containsKey('pong');
              toMain.send([
                'msg',
                decoded,
                isPong ? 0.0 : tRecv - tSentMs,
                convertMs,
                sendMs,
                parseMs,
              ]);
            },
            onDone: () {
              if (gen == connGen) toMain.send(['closed', 'closed by server']);
            },
            onError: (e) {
              if (gen == connGen) toMain.send(['closed', '$e']);
            },
            cancelOnError: true,
          );
          ws = s;
          toMain.send(['open']);
        } catch (e) {
          if (gen == connGen) toMain.send(['closed', '$e']);
        }
        break;
      case 'close':
        connGen++;
        try {
          await ws?.close();
        } catch (_) {}
        ws = null;
        break;
      case 'text':
        ws?.add(msg[1] as String);
        break;
      case 'frame':
        final socket = ws;
        if (socket == null) return;
        final t0 = now();
        final planes = [
          for (final t in (msg[4] as List)) (t as TransferableTypedData).materialize().asUint8List()
        ];
        final frame = {
          'formatName': msg[1],
          'width': msg[2],
          'height': msg[3],
          'planes': planes,
          'yRowStride': msg[5],
          'uvRowStride': msg[6],
          'uvPixelStride': msg[7],
        };
        // Prefer packed YUV420 (half the bytes; server reconstructs the exact
        // same RGB). Fall back to on-device RGB conversion otherwise.
        final packed = YuvPacker.pack(frame);
        final rgb = packed ?? CameraUtils.yuvConverter(frame);
        final flags = _hdrFlagTimestamp | (packed != null ? _hdrFlagYuv420 : 0);
        if (rgb == null) {
          toMain.send(['closed', 'frame conversion failed']);
          return;
        }
        final t1 = now();
        final bytes = rgb['bytes'] as Uint8List;
        final out = Uint8List(20 + bytes.length);
        final bd = ByteData.sublistView(out);
        bd.setInt32(0, (msg[8] as int) | flags, Endian.big);
        bd.setInt32(4, rgb['width'] as int, Endian.big);
        bd.setInt32(8, rgb['height'] as int, Endian.big);
        bd.setInt64(12, msg[9] as int, Endian.big);
        out.setRange(20, out.length, bytes);
        socket.add(out);
        final t2 = now();
        convertMs = t1 - t0;
        sendMs = t2 - t1;
        tSentMs = t2;
        break;
    }
  });
}
