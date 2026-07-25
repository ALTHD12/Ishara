import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';
import '../services/isl_converter_service.dart';
import '../theme/app_themes.dart';
import '../widgets/neo_decorations.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _cameraReady = false;

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
    _initCamera();

    // Load TFLite models in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SignClassifierService>().loadModels();
    });
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    // Prefer front camera for signing (signer faces screen)
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _camera = CameraController(
      cam,
      ResolutionPreset.low, // low = best performance on older phones
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // efficient for ML processing
    );

    await _camera!.initialize();

    // Start feeding frames to the classifier
    _camera!.startImageStream(_onFrame);

    if (mounted) setState(() => _cameraReady = true);
  }

  void _onFrame(CameraImage image) async {
    final classifier = context.read<SignClassifierService>();
    final result = await classifier.processFrame(image);

    if (result == null) return;
    if (!mounted) return;

    // Debounce: only add a new sign if it's different from the last one
    // OR enough frames have passed (person signed it again intentionally)
    setState(() {
      if (result.sign != _lastAddedSign || _holdFrames > _holdThreshold) {
        _glossBuffer.add(result.sign);
        _lastAddedSign = result.sign;
        _holdFrames = 0;
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

  void _undoLast() {
    if (_glossBuffer.isEmpty) return;
    setState(() => _glossBuffer.removeLast());
  }

  void _clear() {
    context.read<SignClassifierService>().resetBuffer();
    setState(() {
      _glossBuffer.clear();
      _englishOutput = '';
      _structureNote = '';
      _lastAddedSign = '';
      _holdFrames = 0;
    });
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
    final theme = Theme.of(context);
    return Scaffold(
      body: DotGridBackground(
        dotColor: theme.colorScheme.outline,
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Text(
                      'ISL LIVE',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.colorScheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Consumer<SignClassifierService>(
                      builder: (_, svc, __) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: svc.isReady
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFD600),
                          borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                          border: AppThemes.neoBorder(theme),
                        ),
                        child: Text(
                          svc.isReady ? '● READY' : '○ LOADING',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Camera preview ─────────────────────────────────────────────
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: AppThemes.neoDecoration(theme, color: Colors.black),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_cameraReady && _camera != null)
                            CameraPreview(_camera!)
                          else
                            Center(
                              child: Text(
                                'STARTING CAMERA...',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),

                          // Corner reticles
                          Positioned.fill(
                            child: CustomPaint(
                              painter: CornerReticlesPainter(
                                color: Colors.white,
                                strokeWidth: 3.0,
                              ),
                            ),
                          ),

                          // Current sign overlay — solid bar at bottom
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              color: Colors.black.withValues(alpha: 0.8),
                              child: Consumer<SignClassifierService>(
                                builder: (_, svc, __) => Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      (svc.currentSign ?? 'WAITING...').toUpperCase(),
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: svc.currentSign != null
                                            ? Colors.white
                                            : Colors.white54,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    if (svc.currentSign != null) ...[
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                        child: Text(
                                          '${(svc.currentConfidence * 100).toInt()}%',
                                          style: const TextStyle(
                                            fontFamily: 'Inter',
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Gloss buffer ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NeoContainer(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'ISL GLOSS',
                            style: AppThemes.labelCaps(theme),
                          ),
                          const Spacer(),
                          // Undo button
                          GestureDetector(
                            onTap: _undoLast,
                            child: Text(
                              'UNDO',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: theme.colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Chip row of detected signs
                      _glossBuffer.isEmpty
                          ? Text(
                              'START SIGNING...',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: _glossBuffer
                                  .asMap()
                                  .entries
                                  .map((e) => NeoChip(
                                        label: e.value,
                                        isActive: e.key == _glossBuffer.length - 1,
                                      ))
                                  .toList(),
                            ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── English output ─────────────────────────────────────────────
              if (_englishOutput.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: NeoContainer(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ENGLISH OUTPUT',
                          style: AppThemes.labelCaps(theme).copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _englishOutput,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: theme.colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_structureNote.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '(${_structureNote})',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 10),

              // ── Action buttons ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: AppThemes.neoShadow(theme),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _glossBuffer.isNotEmpty ? _translate : null,
                          icon: const Text('🤟'),
                          label: const Text('TRANSLATE'),
                          style: ElevatedButton.styleFrom(
                            disabledBackgroundColor: theme.colorScheme.surface,
                            disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: AppThemes.neoShadow(theme),
                        ),
                        child: OutlinedButton(
                          onPressed: _clear,
                          child: const Text('CLEAR'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
