import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';
import '../services/isl_converter_service.dart';
import '../config/live_config.dart';

import '../theme/app_themes.dart';
import '../widgets/neo_decorations.dart';
import '../widgets/connection_status_badge.dart';
import 'package:flutter/foundation.dart';
import '../main.dart'; // To access routeObserver

class ISLToEnglishScreen extends StatefulWidget {
  const ISLToEnglishScreen({super.key});

  @override
  State<ISLToEnglishScreen> createState() => _ISLToEnglishScreenState();
}

class _ISLToEnglishScreenState extends State<ISLToEnglishScreen> with WidgetsBindingObserver, RouteAware {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _isTranslating = false;
  CameraLensDirection _lensDirection = CameraLensDirection.front;

  // Collected gloss words (what the model has detected so far)
  final List<String> _glossBuffer = [];

  // English translation output
  String _englishOutput = '';
  String _structureNote = '';

  // Words arrive as server decision events (majority vote + per-sign repeat
  // cooldown happen server-side; see backend/live_config.py).
  StreamSubscription<String>? _signSub;
  String _currentConsecutiveSign = '';
  int _consecutiveFrames = 0;

  late SignClassifierService _classifierService;
  late ISLConverterService _converterService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _classifierService = context.read<SignClassifierService>();
    _converterService = context.read<ISLConverterService>();

    // Auto-initialize camera on load
    _initCamera();

    // Load TFLite models in background and listen for signs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _classifierService.loadModels();
      _classifierService.addListener(_onClassifierUpdate);
      _signSub = _classifierService.signEvents.listen(_onSignEvent);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPushNext() {
    // Another route was pushed over us (e.g., DataRecorderScreen)
    // Release the camera so the new route can use it
    if (_camera != null && _camera!.value.isInitialized) {
      _camera!.dispose();
      _camera = null;
      _cameraReady = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void didPopNext() {
    // The pushed route was popped. We are visible again.
    if (_camera == null) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _initCamera();
      });
    }
  }

  void _onSignEvent(String sign) {
    if (!mounted || !_isTranslating) return;
    if (LiveConfig.clientConsecutiveThreshold > 1 &&
        _consecutiveFrames < LiveConfig.clientConsecutiveThreshold) {
      return; // optional extra client-side confirmation (off by default)
    }
    setState(() {
      _glossBuffer.add(sign);
      _translate();
    });
  }

  void _onClassifierUpdate() {
    if (!mounted || !_isTranslating) return;
    // Track how many consecutive results showed the same sign (only used when
    // LiveConfig.clientConsecutiveThreshold > 1).
    final currentSign = _classifierService.currentSign ?? '';
    if (currentSign.isNotEmpty && currentSign == _currentConsecutiveSign) {
      _consecutiveFrames++;
    } else {
      _currentConsecutiveSign = currentSign;
      _consecutiveFrames = currentSign.isEmpty ? 0 : 1;
    }
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
      ResolutionPreset.low,
      enableAudio: false,
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
      final oldCamera = _camera;
      _camera = null;
      _cameraReady = false;
      setState(() {});
      await oldCamera!.dispose();
      await Future.delayed(const Duration(milliseconds: 300)); // Allow hardware to release lock
    }
    
    _lensDirection = _lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
        
    await _initCamera();
  }

  void _onFrame(CameraImage image) {
    if (!mounted || !_isTranslating) return;

    _classifierService.processFrame(
      image, 
      _camera!.description.sensorOrientation
    );
  }

  void _translate() async {
    if (_glossBuffer.isEmpty) return;
    final gloss = _glossBuffer.join(' ');
    final result = await _converterService.islToEnglish(gloss);
    
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
        _currentConsecutiveSign = '';
        _consecutiveFrames = 0;
      });
      _classifierService.resetBuffer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      if (_camera != null && _camera!.value.isInitialized) {
        _camera!.dispose();
        _camera = null;
        _cameraReady = false;
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_camera == null) {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _classifierService.removeListener(_onClassifierUpdate);
    _signSub?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ══════════════════════════════════════════════════════════════
              // Camera Feed — neobrutalism card with corner reticles
              // ══════════════════════════════════════════════════════════════
              Container(
                height: 400,
                decoration: AppThemes.neoDecoration(theme, color: Colors.black),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_cameraReady && _camera != null)
                        SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _camera!.value.previewSize?.height ?? 1,
                              height: _camera!.value.previewSize?.width ?? 1,
                              child: Stack(
                                children: [
                                  CameraPreview(_camera!),
                                  // Hand Nodes Overlay
                                  if (_isTranslating)
                                    Positioned.fill(
                                      child: Consumer<SignClassifierService>(
                                        builder: (context, classifier, child) {
                                          return CustomPaint(
                                            painter: HolisticNodePainter(
                                              poseNodes: classifier.poseNodes,
                                              faceNodes: classifier.faceNodes,
                                              leftHandNodes: classifier.leftHandNodes,
                                              rightHandNodes: classifier.rightHandNodes,
                                              isFrontCamera: _lensDirection == CameraLensDirection.front,
                                              theme: theme,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Center(
                          child: Text(
                            'LOADING CAMERA...',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      
                      // Corner reticles overlay
                      Positioned.fill(
                        child: CustomPaint(
                          painter: CornerReticlesPainter(
                            color: Colors.white,
                            strokeWidth: 3.0,
                          ),
                        ),
                      ),

                      // "LIVE" badge — top-left
                      if (_isTranslating)
                        Positioned(
                          top: 16,
                          left: 16,
                          child: NeoBadge(
                            text: 'LIVE',
                            backgroundColor: Colors.black,
                            textColor: Colors.white,
                            leading: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF3B5C),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),

                      // Confidence % — top-right
                      if (_isTranslating)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Consumer<SignClassifierService>(
                            builder: (context, classifier, child) {
                              if (classifier.currentSign == null) return const SizedBox.shrink();
                              return NeoBadge(
                                text: '${(classifier.currentConfidence * 100).toStringAsFixed(0)}%',
                                backgroundColor: Colors.black,
                                textColor: Colors.white,
                              );
                            },
                          ),
                        ),

                      // Debug error display
                      if (_isTranslating)
                        Positioned.fill(
                          child: Consumer<SignClassifierService>(
                            builder: (context, classifier, child) {
                              if (classifier.lastDebugError.isNotEmpty) {
                                return Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 60),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      border: Border.all(color: const Color(0xFFFF3B5C), width: 2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      classifier.lastDebugError,
                                      style: const TextStyle(
                                        color: Color(0xFFFF3B5C),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),

                      // Backend link status — tap: retry, long-press: server settings
                      const Positioned(
                        bottom: 16,
                        left: 16,
                        child: ConnectionStatusBadge(),
                      ),

                      // Camera flip button — neobrutalism square button
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: _switchCamera,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.white,
                                  offset: Offset(3, 3),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.flip_camera_ios,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),

              // ══════════════════════════════════════════════════════════════
              // Action Button — neobrutalism styled
              // ══════════════════════════════════════════════════════════════
              Container(
                decoration: BoxDecoration(
                  boxShadow: AppThemes.neoShadow(theme),
                ),
                child: ElevatedButton.icon(
                  onPressed: _toggleTranslation,
                  icon: Icon(
                    _isTranslating ? Icons.close : Icons.camera_alt,
                    size: 22,
                  ),
                  label: Text(
                    _isTranslating ? 'STOP TRANSLATING' : 'START TRANSLATING',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isTranslating 
                        ? const Color(0xFFFF3B5C)
                        : theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                      side: BorderSide(color: theme.colorScheme.outline, width: AppThemes.borderWidth),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 28),

              // ══════════════════════════════════════════════════════════════
              // ISL Sequence section
              // ══════════════════════════════════════════════════════════════
              if (_glossBuffer.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ISL SEQUENCE',
                      style: AppThemes.labelCaps(theme),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: _glossBuffer.asMap().entries.map((entry) {
                    final isLast = entry.key == _glossBuffer.length - 1;
                    return NeoChip(
                      label: entry.value,
                      isActive: isLast,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // ══════════════════════════════════════════════════════════════
              // Context Statement Card — neobrutalism styled
              // ══════════════════════════════════════════════════════════════
              NeoContainer(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONTEXT STATEMENT',
                      style: AppThemes.labelCaps(theme),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _englishOutput.isNotEmpty 
                          ? '\u201C$_englishOutput\u201D' 
                          : '\u201CWaiting for translation...\u201D',
                      style: AppThemes.quoteText(theme),
                    ),
                    if (_structureNote.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _structureNote,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HolisticNodePainter — neobrutalism bold wireframe overlay
// ══════════════════════════════════════════════════════════════════════════════
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
    // Neobrutalism: thick white lines + solid white dots on dark camera feed
    final handPointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final handLinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
      
    final facePointPaint = Paint()
      ..color = theme.colorScheme.primary
      ..style = PaintingStyle.fill;
    final faceLinePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

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

      for (int i = 0; i < screenNodes.length; i++) {
        canvas.drawCircle(screenNodes[i], radius, pPaint);
      }
    }

    final handConnections = [
      [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
      [0, 5], [5, 6], [6, 7], [7, 8], // Index
      [5, 9], [9, 10], [10, 11], [11, 12], // Middle
      [9, 13], [13, 14], [14, 15], [15, 16], // Ring
      [13, 17], [0, 17], [17, 18], [18, 19], [19, 20] // Pinky
    ];

    final faceConnections = [
      // Right Eyebrow
      [70, 63], [63, 105], [105, 66], [66, 107], [107, 55], [55, 65], [65, 52], [52, 53], [53, 46], // Upper
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

    // Bold thick wireframe — neobrutalism diagram
    drawNodes(leftHandNodes, handConnections, handPointPaint, handLinePaint, 5.0);
    drawNodes(rightHandNodes, handConnections, handPointPaint, handLinePaint, 5.0);
    
    // Face mesh — slightly thinner but still bold
    drawNodes(faceNodes, faceConnections, facePointPaint, faceLinePaint, 1.5);
  }

  @override
  bool shouldRepaint(covariant HolisticNodePainter oldDelegate) => true;
}
