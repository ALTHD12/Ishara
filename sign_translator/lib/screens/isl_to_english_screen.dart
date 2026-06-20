import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';
import '../services/isl_converter_service.dart';
import '../widgets/output_card.dart';
import 'package:flutter/foundation.dart';

class ISLToEnglishScreen extends StatefulWidget {
  const ISLToEnglishScreen({super.key});

  @override
  State<ISLToEnglishScreen> createState() => _ISLToEnglishScreenState();
}

class _ISLToEnglishScreenState extends State<ISLToEnglishScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _isTranslating = false;
  CameraLensDirection _lensDirection = CameraLensDirection.front;

  // Collected gloss words (what the model has detected so far)
  final List<String> _glossBuffer = [];

  // English translation output
  String _englishOutput = '';
  String _structureNote = '';

  // Debounce: avoid adding the same word repeatedly
  String _lastAddedSign = '';
  int _holdFrames = 0;
  static const int _holdThreshold = 15; // frames to hold before accepting next

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Auto-initialize camera on load
    _initCamera();

    // Load TFLite models in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SignClassifierService>().loadModels();
    });
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final cam = cameras.firstWhere(
      (c) => c.lensDirection == _lensDirection,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _camera!.initialize();
      _camera!.startImageStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('CAMERA ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera Error: $e')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_camera != null) {
      await _camera!.stopImageStream();
      await _camera!.dispose();
      _camera = null;
      _cameraReady = false;
    }
    setState(() {
      _lensDirection = _lensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
    });
    await _initCamera();
  }

  void _onFrame(CameraImage image) async {
    if (!mounted || !_isTranslating) return;

    final result = await context.read<SignClassifierService>().processFrame(
      image, 
      _camera!.description.sensorOrientation
    );

    if (result == null) return;
    if (!mounted) return;

    setState(() {
      if (result.sign != _lastAddedSign || _holdFrames > _holdThreshold) {
        _glossBuffer.add(result.sign);
        _lastAddedSign = result.sign;
        _holdFrames = 0;
        _translate();
      } else {
        _holdFrames++;
      }
    });
  }

  void _translate() async {
    if (_glossBuffer.isEmpty) return;
    final gloss = _glossBuffer.join(' ');
    final result = await context.read<ISLConverterService>().islToEnglish(gloss);
    
    if (mounted) {
      setState(() {
        _englishOutput = result.output;
        _structureNote = result.structureNote;
      });
    }
  }

  void _toggleTranslation() {
    if (_isTranslating) {
      // Stop translating
      setState(() {
        _isTranslating = false;
      });
    } else {
      // Start translating
      setState(() {
        _isTranslating = true;
        _glossBuffer.clear();
        _englishOutput = '';
        _structureNote = '';
        _lastAddedSign = '';
        _holdFrames = 0;
      });
      context.read<SignClassifierService>().resetBuffer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_camera == null || !_camera!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _camera!.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Camera Preview Area
          Container(
            height: 400,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _cameraReady && _camera != null
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: 1 / _camera!.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(_camera!),
                        // Hand Nodes Overlay
                        if (_isTranslating)
                          Positioned.fill(
                            child: Consumer<SignClassifierService>(
                              builder: (context, classifier, child) {
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CustomPaint(
                                      painter: HolisticNodePainter(
                                        poseNodes: classifier.poseNodes,
                                        faceNodes: classifier.faceNodes,
                                        leftHandNodes: classifier.leftHandNodes,
                                        rightHandNodes: classifier.rightHandNodes,
                                        isFrontCamera: _camera!.description.lensDirection == CameraLensDirection.front,
                                      ),
                                    ),
                                    if (classifier.lastDebugError.isNotEmpty)
                                      Positioned(
                                        top: 16,
                                        left: 16,
                                        right: 16,
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          color: Colors.black87,
                                          child: Text(
                                            classifier.lastDebugError,
                                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        // Camera Switch Button
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: IconButton.filledTonal(
                            onPressed: _switchCamera,
                            icon: const Icon(Icons.flip_camera_ios),
                            tooltip: 'Switch Camera',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Connecting to Camera...',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Primary Action Button
          FilledButton(
            onPressed: _toggleTranslation,
            style: FilledButton.styleFrom(
              backgroundColor: _isTranslating ? Colors.red : Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _isTranslating ? 'Stop Translating' : 'Translate',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),

          // Translation Output Cards
          OutputCard(
            title: 'ISL Sequence',
            content: _glossBuffer.isNotEmpty ? _glossBuffer.join(' ') : 'Waiting for signs...',
          ),
          const SizedBox(height: 16),
          OutputCard(
            title: 'Context-Based Statement',
            content: _englishOutput.isNotEmpty 
                ? (_structureNote.isNotEmpty 
                    ? '$_englishOutput\n($_structureNote)' 
                    : _englishOutput)
                : 'Translation will appear here...',
          ),
        ],
      ),
    );
  }
}

class HolisticNodePainter extends CustomPainter {
  final List<Offset> poseNodes;
  final List<Offset> faceNodes;
  final List<Offset> leftHandNodes;
  final List<Offset> rightHandNodes;
  final bool isFrontCamera;

  HolisticNodePainter({
    required this.poseNodes,
    required this.faceNodes,
    required this.leftHandNodes,
    required this.rightHandNodes,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final posePointPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final poseLinePaint = Paint()..color = Colors.white70..strokeWidth = 2.0..style = PaintingStyle.stroke;

    final handPointPaint = Paint()..color = Colors.blueAccent..style = PaintingStyle.fill;
    final handLinePaint = Paint()..color = Colors.pinkAccent..strokeWidth = 2.0..style = PaintingStyle.stroke;
      
    final facePointPaint = Paint()..color = Colors.greenAccent..style = PaintingStyle.fill;
    final faceLinePaint = Paint()..color = Colors.greenAccent..strokeWidth = 1.5..style = PaintingStyle.stroke;

    void drawNodes(List<Offset> nodes, List<List<int>> connections, Paint pPaint, Paint lPaint, double radius) {
      if (nodes.isEmpty) return;
      final screenNodes = nodes.map((node) {
        final x = (isFrontCamera ? 1.0 - node.dx : node.dx) * size.width;
        final y = node.dy * size.height;
        return Offset(x, y);
      }).toList();

      for (final c in connections) {
        if (c[0] < screenNodes.length && c[1] < screenNodes.length) {
          canvas.drawLine(screenNodes[c[0]], screenNodes[c[1]], lPaint);
        }
      }

      for (final screenNode in screenNodes) {
        canvas.drawCircle(screenNode, radius, pPaint);
      }
    }

    const handConnections = [
      [0, 1], [1, 2], [2, 3], [3, 4],
      [0, 5], [5, 6], [6, 7], [7, 8],
      [5, 9], [9, 10], [10, 11], [11, 12],
      [9, 13], [13, 14], [14, 15], [15, 16],
      [13, 17], [17, 18], [18, 19], [19, 20],
      [0, 17]
    ];

    const faceConnections = [
      // Right Eyebrow
      [35, 124], [124, 46], [46, 53], [53, 52], [52, 65], // Lower
      [156, 70], [70, 63], [63, 105], [105, 66], [66, 107], [107, 55], [55, 193], // Upper
      // Left Eyebrow
      [265, 353], [353, 276], [276, 283], [283, 282], [282, 295], // Lower
      [383, 300], [300, 293], [293, 334], [334, 296], [296, 336], [336, 285], [285, 417], // Upper
      // Lips Outer
      [61, 146], [146, 91], [91, 181], [181, 84], [84, 17], [17, 314], [314, 405], [405, 321], [321, 375], [375, 291],
      [61, 185], [185, 40], [40, 39], [39, 37], [37, 0], [0, 267], [267, 269], [269, 270], [270, 409], [409, 291],
      // Lips Inner
      [78, 95], [95, 88], [88, 178], [178, 87], [87, 14], [14, 317], [317, 402], [402, 318], [318, 324], [324, 308],
      [78, 191], [191, 80], [80, 81], [81, 82], [82, 13], [13, 312], [312, 311], [311, 310], [310, 415], [415, 308],
    ];

    // drawNodes(poseNodes, poseConnections, posePointPaint, poseLinePaint, 4.0); // Hidden by request
    drawNodes(leftHandNodes, handConnections, handPointPaint, handLinePaint, 3.0);
    drawNodes(rightHandNodes, handConnections, handPointPaint, handLinePaint, 3.0);
    
    // Draw face mesh with expressive connections
    drawNodes(faceNodes, faceConnections, facePointPaint, faceLinePaint, 1.5);
  }

  @override
  bool shouldRepaint(covariant HolisticNodePainter oldDelegate) => true;
}
