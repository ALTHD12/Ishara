import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../utils/camera_utils.dart';

class SignResult {
  final String sign;
  final double confidence;
  const SignResult({required this.sign, required this.confidence});
}

class SignClassifierService extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isReady = false;
  bool get isReady => _isReady;

  String? _currentSign;
  double  _currentConfidence = 0.0;
  String? get currentSign        => _currentSign;
  double  get currentConfidence  => _currentConfidence;

  String _lastDebugError = '';
  String get lastDebugError => _lastDebugError;

  // Holistic node visualization
  List<Offset> _poseNodes = [];
  List<Offset> _faceNodes = [];
  List<Offset> _leftHandNodes = [];
  List<Offset> _rightHandNodes = [];

  List<Offset> get poseNodes => _poseNodes;
  List<Offset> get faceNodes => _faceNodes;
  List<Offset> get leftHandNodes => _leftHandNodes;
  List<Offset> get rightHandNodes => _rightHandNodes;

  int _frameCounter = 0;
  bool _isProcessingFrame = false;

  Future<void> loadModels() async {
    try {
      // Connect to Python backend using centralized config
      _channel = WebSocketChannel.connect(
        Uri.parse(AppConfig.backendWsUrl),
      );
      
      // Listen for incoming holistic JSON data
      _channel!.stream.listen(
        (message) {
          _handleHolisticResponse(message);
        },
        onError: (e) {
          _lastDebugError = 'WebSocket Error: $e. Is the python backend running?';
          notifyListeners();
        },
        onDone: () {
          _lastDebugError = 'WebSocket Disconnected. Did the python server crash?';
          _isReady = false;
          notifyListeners();
        }
      );

      _isReady = true;
      notifyListeners();
      debugPrint('✅ Connected to Python Holistic Backend');
    } catch (e) {
      _lastDebugError = '❌ WebSocket connection failed: $e';
      notifyListeners();
      debugPrint('❌ WebSocket connection failed: $e');
    }
  }

  void _handleHolisticResponse(String jsonString) {
    _isProcessingFrame = false; // unlock for next frame
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      
      _poseNodes = _parseNodes(data['pose']);
      _faceNodes = _parseNodes(data['face']);
      _leftHandNodes = _parseNodes(data['left_hand']);
      _rightHandNodes = _parseNodes(data['right_hand']);
      
      _lastDebugError = '';
      notifyListeners();
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
    if (!_isReady || _channel == null || _isProcessingFrame) return null;

    _isProcessingFrame = true;

    try {
      // Extract bytes before passing to isolate
      final formatName = image.format.group.name;
      final width = image.width;
      final height = image.height;
      final List<Uint8List> planes = image.planes.map((p) => p.bytes).toList();
      
      int yRowStride = width;
      int uvRowStride = width ~/ 2;
      int uvPixelStride = 1;
      
      if (formatName != 'bgra8888' && image.planes.length >= 3) {
        yRowStride = image.planes[0].bytesPerRow;
        uvRowStride = image.planes[1].bytesPerRow;
        uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      }
      
      // Run the heavy math in a background thread to prevent UI lag
      final result = await compute(CameraUtils.yuvConverter, {
        'formatName': formatName,
        'width': width,
        'height': height,
        'planes': planes,
        'yRowStride': yRowStride,
        'uvRowStride': uvRowStride,
        'uvPixelStride': uvPixelStride,
      });

      if (result == null) {
        _isProcessingFrame = false;
        _lastDebugError = 'YUV conversion failed in isolate';
        notifyListeners();
        return null;
      }

      final outWidth = result['width'] as int;
      final outHeight = result['height'] as int;
      final rgbBytes = result['bytes'] as Uint8List;

      // Create binary payload: 4 bytes width, 4 bytes height, 4 bytes rotation, RGB payload
      final header = ByteData(12);
      header.setInt32(0, outWidth, Endian.big);
      header.setInt32(4, outHeight, Endian.big);
      header.setInt32(8, sensorOrientation, Endian.big);
      
      final payload = BytesBuilder(copy: false);
      payload.add(header.buffer.asUint8List());
      payload.add(rgbBytes);
      
      _channel!.sink.add(payload.toBytes());
      
      return null;
    } catch (e) {
      _lastDebugError = 'processFrame exception: $e';
      _isProcessingFrame = false;
      notifyListeners();
      return null;
    }
  }

  // Replaced by CameraUtils.yuvConverter

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
    _channel?.sink.close();
    super.dispose();
  }
}
