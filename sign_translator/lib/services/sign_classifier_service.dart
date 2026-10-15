import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import '../config/app_config.dart';
import '../config/live_config.dart';
import '../utils/latency_stats.dart';
import 'frame_link.dart';

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
  static const Duration _backoffMin = Duration(milliseconds: 500);
  static const Duration _backoffMax = Duration(seconds: 8);
  static const Duration _heartbeatEvery = Duration(seconds: 2);
  /// No message at all (result or pong) for this long => link is dead.
  static const Duration _deadAfter = Duration(seconds: 6);

  final FrameLink _link = FrameLink();
  StreamSubscription? _linkSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _attempt = 0;
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

  /// Emits a word each time the server makes a new decision (event id
  /// increases). Repeats of the same sign are allowed after the server's
  /// cooldown.
  final StreamController<String> _signEvents = StreamController<String>.broadcast();
  Stream<String> get signEvents => _signEvents.stream;
  int _lastEventId = 0;

  String _lastDebugError = '';
  String get lastDebugError => _lastDebugError;

  String _recordingStatus = '';
  String get recordingStatus => _recordingStatus;

  // Holistic node visualization (latest result only)
  List<Offset> _poseNodes = [];
  List<Offset> _faceNodes = [];
  List<Offset> _leftHandNodes = [];
  List<Offset> _rightHandNodes = [];

  List<Offset> get poseNodes => _poseNodes;
  List<Offset> get faceNodes => _faceNodes;
  List<Offset> get leftHandNodes => _leftHandNodes;
  List<Offset> get rightHandNodes => _rightHandNodes;

  // ── Backpressure ──
  bool _inFlight = false;
  double _inFlightSinceMs = 0;
  double _lastSendMs = -1e9;

  // ── Latency instrumentation (ISL_DEBUG_TIMING) ──
  final Stopwatch _clock = Stopwatch()..start();
  final LatencyStats _stats = LatencyStats('client');
  double _tCapture = 0;
  double _handoffMs = 0;
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
    _setStatus(_attempt == 0 ? ConnectionStatus.connecting : ConnectionStatus.reconnecting);
    await _link.start();
    _linkSub ??= _link.events.listen(_onLinkEvent);
    _link.connect(AppConfig.backendWsUrl);
  }

  void _onLinkEvent(List<Object?> e) {
    switch (e[0]) {
      case 'open':
        _attempt = 0;
        _isReady = true;
        _inFlight = false;
        _lastRx = DateTime.now();
        _lastDebugError = '';
        _setStatus(ConnectionStatus.connected);
        _startHeartbeat();
        debugPrint('Connected to backend ${AppConfig.backendWsUrl}');
        break;
      case 'closed':
        if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting ||
            _status == ConnectionStatus.reconnecting) {
          _lastDebugError = _status == ConnectionStatus.connected
              ? 'Connection lost'
              : 'Cannot reach ${AppConfig.server}';
          debugPrint('WebSocket closed: ${e[1]}');
          _onLinkLost();
        }
        break;
      case 'msg':
        _lastRx = DateTime.now();
        final data = e[1];
        if (data is Map) {
          _handleResult(data.cast<String, dynamic>(), (e[2] as num).toDouble(),
              (e[3] as num).toDouble(), (e[4] as num).toDouble(), (e[5] as num).toDouble());
        }
        break;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatEvery, (_) {
      if (!_isReady) return;
      if (DateTime.now().difference(_lastRx) > _deadAfter) {
        _lastDebugError = 'Backend not responding';
        _onLinkLost();
        return;
      }
      _pingSentUs = _clock.elapsedMicroseconds;
      _link.sendText('{"action":"ping"}');
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _link.close();
    _isReady = false;
    _inFlight = false;
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

  void _handleResult(Map<String, dynamic> data, double rttMs, double convertMs,
      double sendMs, double parseMs) {
    if (data.containsKey('pong')) {
      if (_pingSentUs > 0) {
        _lastPingRtt = Duration(microseconds: _clock.elapsedMicroseconds - _pingSentUs);
        notifyListeners();
      }
      return;
    }
    final tRecv = _nowMs;
    _inFlight = false; // unlock for next frame

    _poseNodes = _parseNodes(data['pose']);
    _faceNodes = _parseNodes(data['face']);
    _leftHandNodes = _parseNodes(data['left_hand']);
    _rightHandNodes = _parseNodes(data['right_hand']);

    if (data['sign'] != null) {
      _currentSign = data['sign'] as String;
      _currentConfidence = (data['confidence'] as num).toDouble();
    } else {
      _currentSign = null;
      _currentConfidence = 0.0;
    }

    final eid = data['eid'];
    if (eid is int && eid > _lastEventId) {
      _lastEventId = eid;
      final s = data['esign'];
      if (s is String) _signEvents.add(s);
    }

    _recordingStatus = (data['recording_status'] as String?) ?? '';
    _lastDebugError = '';
    notifyListeners();

    if (LatencyStats.enabled) {
      final server = (data['_t'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toDouble())) ??
          const <String, double>{};
      final serverTotal = server['server_total'] ?? 0.0;
      final tCapture = _tCapture;
      final stages = <String, double>{
        'ui_handoff': _handoffMs,
        'convert(iso)': convertMs,
        'send(iso)': sendMs,
        'rtt': rttMs,
        'network+queue': rttMs - serverTotal,
        'parse(iso)': parseMs,
        'dropped': _droppedSinceSend.toDouble(),
        for (final e in server.entries) 's.${e.key}': e.value,
      };
      _droppedSinceSend = 0;
      // "overlay drawn" = next rasterised frame after this result
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final tDrawn = _nowMs;
        stages['result->drawn'] = tDrawn - tRecv;
        stages['capture->drawn'] = tDrawn - tCapture;
        _stats.record(stages);
      });
    }
  }

  List<Offset> _parseNodes(dynamic list) {
    if (list == null) return const [];
    // Compact [[x, y], ...] in normalized [0, 1] coordinates of the upright frame.
    return [
      for (final n in list as List)
        if (n is List)
          Offset((n[0] as num).toDouble(), (n[1] as num).toDouble())
        else
          Offset((n['x'] as num).toDouble(), (n['y'] as num).toDouble())
    ];
  }

  /// Called for every camera frame. Sends at most one frame in flight and at
  /// most [maxFps] frames/s; everything else is dropped here, cheaply.
  Future<SignResult?> processFrame(CameraImage image, int sensorOrientation,
      {double maxFps = LiveConfig.maxSendFps}) async {
    if (!_isReady) return null;
    final now = _nowMs;
    if (_inFlight) {
      if (now - _inFlightSinceMs < LiveConfig.resultTimeout.inMilliseconds) {
        _droppedSinceSend++;
        return null;
      }
      _inFlight = false; // result lost: don't stall forever
    }
    if (maxFps > 0 && now - _lastSendMs < 1000.0 / maxFps) {
      _droppedSinceSend++;
      return null;
    }

    try {
      _inFlight = true;
      _inFlightSinceMs = now;
      _lastSendMs = now;
      _tCapture = now;
      _link.sendFrame(
        format: image.format.group.name,
        width: image.width,
        height: image.height,
        planes: [for (final p in image.planes) p.bytes],
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
        uvPixelStride: image.planes.length > 1 ? (image.planes[1].bytesPerPixel ?? 1) : 0,
        rotation: sensorOrientation,
        captureUs: _clock.elapsedMicroseconds,
      );
      _handoffMs = _nowMs - now;
    } catch (e) {
      _lastDebugError = 'processFrame exception: $e';
      _inFlight = false;
      notifyListeners();
    }
    return null;
  }

  void startContinuousRecording(String label) {
    if (_isReady) {
      _link.sendText(jsonEncode({
        "action": "start_continuous_recording",
        "label": label,
      }));
    }
  }

  void triggerTraining() {
    if (_isReady) {
      _link.sendText(jsonEncode({"action": "train_model"}));
    }
  }

  void resetBuffer() {
    _poseNodes = [];
    _faceNodes = [];
    _leftHandNodes = [];
    _rightHandNodes = [];
    _currentSign = null;
    _currentConfidence = 0;
    if (_isReady) _link.sendText('{"action":"reset"}');
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _closeSocket();
    _linkSub?.cancel();
    _link.dispose();
    _signEvents.close();
    super.dispose();
  }
}
