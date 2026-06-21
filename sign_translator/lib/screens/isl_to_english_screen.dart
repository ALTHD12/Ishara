import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';
import '../services/isl_converter_service.dart';

import '../theme/app_themes.dart';
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
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1.5,
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
                                          theme: Theme.of(context),
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
          
          // Primary Action Button (Plum pill when translating)
          FilledButton.icon(
            onPressed: _toggleTranslation,
            icon: Icon(
              _isTranslating ? Icons.close : Icons.camera_alt,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            label: Text(
              _isTranslating ? 'Stop Translating' : 'Start Translating',
              style: AppThemes.buttonLabel(Theme.of(context)).copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _isTranslating 
                  ? const Color(0xFF880E4F) // Strict plum color requested
                  : Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 20),
              minimumSize: const Size.fromHeight(60), // full width
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30), // pill shaped
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Sequence Chips Section
          if (_glossBuffer.isNotEmpty) ...[
            Text(
              'ISL SEQUENCE',
              style: AppThemes.labelCaps(Theme.of(context)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _glossBuffer.map((gloss) {
                return Chip(
                  label: Text(gloss),
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                  labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Context Statement Card
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTEXT STATEMENT',
                    style: AppThemes.labelCaps(Theme.of(context)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _englishOutput.isNotEmpty 
                        ? '“$_englishOutput”' 
                        : '“Waiting for translation...”',
                    style: AppThemes.quoteText(Theme.of(context)),
                  ),
                  if (_structureNote.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _structureNote,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ]
                ],
              ),
            ),
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
  final ThemeData theme;

  HolisticNodePainter({
    required this.poseNodes,
    required this.faceNodes,
    required this.leftHandNodes,
    required this.rightHandNodes,
    this.isFrontCamera = false,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // final posePointPaint = Paint()..color = theme.colorScheme.onSurface..style = PaintingStyle.fill;
    // final poseLinePaint = Paint()..color = theme.colorScheme.onSurfaceVariant..strokeWidth = 2.0..style = PaintingStyle.stroke;

    final handPointPaint = Paint()..color = Colors.redAccent..style = PaintingStyle.fill;
    final handLinePaint = Paint()..color = Colors.redAccent..strokeWidth = 2.0..style = PaintingStyle.stroke;
      
    final facePointPaint = Paint()..color = Colors.greenAccent..style = PaintingStyle.fill;
    final faceLinePaint = Paint()..color = Colors.greenAccent..strokeWidth = 1.0..style = PaintingStyle.stroke;

    void drawNodes(List<Offset> nodes, List<List<int>> connections, Paint pPaint, Paint lPaint, double radius, {bool onlyConnectedNodes = false}) {
      if (nodes.isEmpty) return;
      final screenNodes = nodes.map((node) {
        final x = (isFrontCamera ? 1.0 - node.dx : node.dx) * size.width;
        final y = node.dy * size.height;
        return Offset(x, y);
      }).toList();

      Set<int> connectedIndices = {};

      for (final c in connections) {
        if (c[0] < screenNodes.length && c[1] < screenNodes.length) {
          canvas.drawLine(screenNodes[c[0]], screenNodes[c[1]], lPaint);
          connectedIndices.add(c[0]);
          connectedIndices.add(c[1]);
        }
      }

      for (int i = 0; i < screenNodes.length; i++) {
        if (onlyConnectedNodes && !connectedIndices.contains(i)) continue;
        canvas.drawCircle(screenNodes[i], radius, pPaint);
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
      // Right Eye
      [33, 7], [7, 163], [163, 144], [144, 145], [145, 153], [153, 154], [154, 155], [155, 133], [133, 173], [173, 157], [157, 158], [158, 159], [159, 160], [160, 161], [161, 246], [246, 33],
      // Left Eye
      [362, 382], [382, 381], [381, 380], [380, 374], [374, 373], [373, 390], [390, 249], [249, 263], [263, 466], [466, 388], [388, 387], [387, 386], [386, 385], [385, 384], [384, 398], [398, 362],
      // Lips Outer
      [61, 146], [146, 91], [91, 181], [181, 84], [84, 17], [17, 314], [314, 405], [405, 321], [321, 375], [375, 291],
      [61, 185], [185, 40], [40, 39], [39, 37], [37, 0], [0, 267], [267, 269], [269, 270], [270, 409], [409, 291],
      // Lips Inner
      [78, 95], [95, 88], [88, 178], [178, 87], [87, 14], [14, 317], [317, 402], [402, 318], [318, 324], [324, 308],
      [78, 191], [191, 80], [80, 81], [81, 82], [82, 13], [13, 312], [312, 311], [311, 310], [310, 415], [415, 308],
      // Face Oval
      [10, 338], [338, 297], [297, 332], [332, 284], [284, 251], [251, 389], [389, 356], [356, 454], [454, 323], [323, 361], [361, 288], [288, 397], [397, 365], [365, 379], [379, 378], [378, 400], [400, 377], [377, 152], [152, 148], [148, 176], [176, 149], [149, 150], [150, 136], [136, 172], [172, 58], [58, 132], [132, 93], [93, 234], [234, 127], [127, 162], [162, 21], [21, 54], [54, 103], [103, 67], [67, 109], [109, 10]
    ];

    drawNodes(leftHandNodes, handConnections, handPointPaint, handLinePaint, 3.0);
    drawNodes(rightHandNodes, handConnections, handPointPaint, handLinePaint, 3.0);
    
    // Draw face mesh ONLY for connected points so eyebrows are visible and not buried in points
    drawNodes(faceNodes, faceConnections, facePointPaint, faceLinePaint, 1.5, onlyConnectedNodes: true);
  }

  @override
  bool shouldRepaint(covariant HolisticNodePainter oldDelegate) => true;
}
