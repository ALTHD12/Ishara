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
          _lastDebugError = 'WebSocket Disconnected. Reconnecting in 3s...';
          _isReady = false;
          _isProcessingFrame = false;
          notifyListeners();
          
          // Auto-reconnect after 3 seconds
          Future.delayed(const Duration(seconds: 3), () {
            if (!_isReady) {
              loadModels();
            }
          });
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
    _channel?.sink.close();
    super.dispose();
  }
}
