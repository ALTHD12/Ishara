import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../utils/camera_utils.dart';
import '../utils/latency_stats.dart';

class SignResult {
  final String sign;
  final double confidence;
  const SignResult({required this.sign, required this.confidence});
}

enum ConnectionStatus { disconnected, connecting, connected, reconnecting, paused }

class SignClassifierService extends ChangeNotifier with WidgetsBindingObserver {
  SignClassifierService() {
    WidgetsBinding.instance.addObserver(this);
  }

  // ── Connection tuning ──
  static const Duration _connectTimeout = Duration(seconds: 4);
  static const Duration _backoffMin = Duration(milliseconds: 500);
  static const Duration _backoffMax = Duration(seconds: 8);
  static const Duration _heartbeatEvery = Duration(seconds: 2);
  /// No message at all (result or pong) for this long => link is dead.
  static const Duration _deadAfter = Duration(seconds: 6);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _attempt = 0;
  int _generation = 0; // invalidates callbacks from stale sockets
  bool _wantConnected = false; // a screen asked for the backend
  bool _appPaused = false;
  DateTime _lastRx = DateTime.now();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;
  String get serverAddress => AppConfig.server;
  Duration? _lastPingRtt;
  Duration? get lastPingRtt => _lastPingRtt;
  int _pingSentUs = 0;

  bool _isReady = false;
  bool get isReady => _isReady;

  String? _currentSign;
  double  _currentConfidence = 0.0;
  String? get currentSign        => _currentSign;
  double  get currentConfidence  => _currentConfidence;

  String _lastDebugError = '';
  String get lastDebugError => _lastDebugError;

  String _recordingStatus = '';
  String get recordingStatus => _recordingStatus;

  // Holistic node visualization
  List<Offset> _poseNodes = [];
  List<Offset> _faceNodes = [];
  List<Offset> _leftHandNodes = [];
  List<Offset> _rightHandNodes = [];

  List<Offset> get poseNodes => _poseNodes;
  List<Offset> get faceNodes => _faceNodes;
  List<Offset> get leftHandNodes => _leftHandNodes;
  List<Offset> get rightHandNodes => _rightHandNodes;

  bool _isProcessingFrame = false;

  // ── Latency instrumentation (ISL_DEBUG_TIMING) ──
  final Stopwatch _clock = Stopwatch()..start();
  final LatencyStats _stats = LatencyStats('client');
  double _tCapture = 0, _tSent = 0, _convertMs = 0, _sendMs = 0;
  int _droppedSinceSend = 0;
  double get _nowMs => _clock.elapsedMicroseconds / 1000.0;

  /// Kept for existing callers: ensures a live connection (idempotent).
  Future<void> loadModels() => connect();

  /// Open the WebSocket if not already open/connecting. Safe to call repeatedly.
  Future<void> connect() async {
    _wantConnected = true;
    if (_appPaused) return;
    if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) return;
    _reconnectTimer?.cancel();
    await _open();
  }

  /// Change the server and reconnect immediately.
  Future<void> setServer(String address) async {
    await AppConfig.setServer(address);
    await reconnectNow();
  }

  /// Retry right now (e.g. user tapped the status badge).
  Future<void> reconnectNow() async {
    _attempt = 0;
    _reconnectTimer?.cancel();
    _closeSocket();
    _wantConnected = true;
    _setStatus(ConnectionStatus.disconnected);
    if (!_appPaused) await _open();
  }

  Future<void> _open() async {
    final gen = ++_generation;
    _setStatus(_attempt == 0 ? ConnectionStatus.connecting : ConnectionStatus.reconnecting);
    final url = AppConfig.backendWsUrl;
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      await ch.ready.timeout(_connectTimeout);
      if (gen != _generation) { ch.sink.close(); return; } // superseded
      _channel = ch;
      _lastRx = DateTime.now();
      _sub = ch.stream.listen(
        (message) {
          if (gen != _generation) return;
          _lastRx = DateTime.now();
          if (message is String) _handleHolisticResponse(message);
        },
        onError: (e) {
          if (gen != _generation) return;
          _lastDebugError = 'WebSocket error: $e';
          _onLinkLost();
        },
        onDone: () {
          if (gen != _generation) return;
          _onLinkLost();
        },
        cancelOnError: true,
      );
      _attempt = 0;
      _isReady = true;
      _isProcessingFrame = false;
      _lastDebugError = '';
      _setStatus(ConnectionStatus.connected);
      _startHeartbeat(gen);
      debugPrint('Connected to backend $url');
    } catch (e) {
      if (gen != _generation) return;
      _lastDebugError = 'Cannot reach $url';
      debugPrint('WebSocket connect failed ($url): $e');
      _onLinkLost();
    }
  }

  void _startHeartbeat(int gen) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatEvery, (_) {
      if (gen != _generation || _channel == null) return;
      if (DateTime.now().difference(_lastRx) > _deadAfter) {
        _lastDebugError = 'Backend not responding';
        _onLinkLost();
        return;
      }
      _pingSentUs = _clock.elapsedMicroseconds;
      try {
        _channel!.sink.add('{"action":"ping"}');
      } catch (_) {
        _onLinkLost();
      }
    });
  }

  void _onLinkLost() {
    _closeSocket();
    if (!_wantConnected || _appPaused) {
      _setStatus(_appPaused ? ConnectionStatus.paused : ConnectionStatus.disconnected);
      return;
    }
    // Exponential backoff with jitter: ~0.5s, 1s, 2s, 4s, 8s, 8s...
    final base = _backoffMin.inMilliseconds * pow(2, min(_attempt, 10));
    final capped = min(base.toInt(), _backoffMax.inMilliseconds);
    final delay = Duration(milliseconds: (capped * (0.8 + Random().nextDouble() * 0.4)).round());
    _attempt++;
    _setStatus(ConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_wantConnected && !_appPaused) _open();
    });
  }

  void _closeSocket() {
    _generation++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isReady = false;
    _isProcessingFrame = false;
  }

  void _setStatus(ConnectionStatus s) {
    _status = s;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Background: drop the socket so the server frees its per-client state.
      // Reconnect immediately on resume.
      _appPaused = true;
      _reconnectTimer?.cancel();
      _closeSocket();
      _setStatus(ConnectionStatus.paused);
    } else if (state == AppLifecycleState.resumed && _appPaused) {
      _appPaused = false;
      if (_wantConnected) {
        _attempt = 0;
        _open();
      }
    }
  }

  void _handleHolisticResponse(String jsonString) {
    final tRecv = _nowMs;
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      if (data.containsKey('pong')) {
        if (_pingSentUs > 0) {
          _lastPingRtt = Duration(microseconds: _clock.elapsedMicroseconds - _pingSentUs);
        }
        return;
      }
      _isProcessingFrame = false; // unlock for next frame
      final tParsed = _nowMs;
      
      _poseNodes = _parseNodes(data['pose']);
      _faceNodes = _parseNodes(data['face']);
      _leftHandNodes = _parseNodes(data['left_hand']);
      _rightHandNodes = _parseNodes(data['right_hand']);
      
      // Extract Model Prediction if available
      if (data.containsKey('sign') && data['sign'] != null) {
        _currentSign = data['sign'] as String;
        _currentConfidence = (data['confidence'] as num).toDouble();
      } else {
        _currentSign = null;
        _currentConfidence = 0.0;
      }
      
      if (data.containsKey('recording_status')) {
        _recordingStatus = data['recording_status'] as String;
      } else {
        _recordingStatus = '';
      }
      
      _lastDebugError = '';
      notifyListeners();

      if (LatencyStats.enabled && _tSent > 0) {
        final server = (data['_t'] as Map?)?.map(
                (k, v) => MapEntry(k as String, (v as num).toDouble())) ??
            const <String, double>{};
        final serverTotal = server['server_total'] ?? 0.0;
        final rtt = tRecv - _tSent;
        final tCapture = _tCapture;
        final stages = <String, double>{
          'convert': _convertMs,
          'send': _sendMs,
          'rtt': rtt,
          'network+queue': rtt - serverTotal,
          'parse': tParsed - tRecv,
          'dropped': _droppedSinceSend.toDouble(),
          for (final e in server.entries) 's.${e.key}': e.value,
        };
        // "overlay drawn" = next rasterised frame after this result
        SchedulerBinding.instance.addPostFrameCallback((_) {
          final tDrawn = _nowMs;
          stages['result->drawn'] = tDrawn - tRecv;
          stages['capture->drawn'] = tDrawn - tCapture;
          _stats.record(stages);
        });
      }
    } catch(e) {
      _lastDebugError = 'JSON parse error: $e';
      notifyListeners();
    }
  }

  List<Offset> _parseNodes(dynamic list) {
    if (list == null) return [];
    return (list as List).map((node) {
      // MediaPipe Python outputs normalized coordinates [0.0, 1.0]
      return Offset((node['x'] as num).toDouble(), (node['y'] as num).toDouble());
    }).toList();
  }

  Future<SignResult?> processFrame(CameraImage image, int sensorOrientation) async {
    if (!_isReady || _channel == null || _isProcessingFrame) {
      _droppedSinceSend++;
      return null;
    }

    _isProcessingFrame = true;
    final tCapture = _nowMs;

    try {
      final rgbData = CameraUtils.yuvConverter({
        'formatName': image.format.group.name,
        'width': image.width,
        'height': image.height,
        'planes': image.planes.map((p) => p.bytes).toList(),
        'yRowStride': image.planes[0].bytesPerRow,
        'uvRowStride': image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
        'uvPixelStride': image.planes.length > 1 ? image.planes[1].bytesPerPixel : 0,
      });

      if (rgbData == null) {
        _lastDebugError = 'YUV Conversion failed';
        _isProcessingFrame = false;
        notifyListeners();
        return null;
      }

      final tConverted = _nowMs;
      final outWidth = rgbData['width'] as int;
      final outHeight = rgbData['height'] as int;
      final rgbBytes = rgbData['bytes'] as Uint8List;

      final header = ByteData(12);
      header.setInt32(0, sensorOrientation, Endian.big);
      header.setInt32(4, outWidth, Endian.big);
      header.setInt32(8, outHeight, Endian.big);
      
      final payload = BytesBuilder(copy: false);
      payload.add(header.buffer.asUint8List());
      payload.add(rgbBytes);
      
      _channel!.sink.add(payload.toBytes());

      final tSent = _nowMs;
      _tCapture = tCapture;
      _convertMs = tConverted - tCapture;
      _sendMs = tSent - tConverted;
      _tSent = tSent;
      _droppedSinceSend = 0;
      
      return null;
    } catch (e) {
      _lastDebugError = 'processFrame exception: $e';
      _isProcessingFrame = false;
      notifyListeners();
      return null;
    }
  }

  // Replaced by CameraUtils.yuvConverter

  void startContinuousRecording(String label) {
    if (_channel != null && _isReady) {
      final cmd = jsonEncode({
        "action": "start_continuous_recording",
        "label": label,
      });
      _channel!.sink.add(cmd);
    }
  }

  void triggerTraining() {
    if (_channel != null && _isReady) {
      final cmd = jsonEncode({
        "action": "train_model"
      });
      _channel!.sink.add(cmd);
    }
  }

  void resetBuffer() {
    _poseNodes = [];
    _faceNodes = [];
    _leftHandNodes = [];
    _rightHandNodes = [];
    _currentSign = null;
    _currentConfidence = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _closeSocket();
    super.dispose();
  }
}
