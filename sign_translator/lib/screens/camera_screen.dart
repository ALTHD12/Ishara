import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';
import '../services/isl_converter_service.dart';

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
      ResolutionPreset.medium, // medium = good balance speed/quality
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

  void _translate() {
    if (_glossBuffer.isEmpty) return;
    final gloss = _glossBuffer.join(' ');
    final result = context.read<ISLConverterService>().islToEnglish(gloss);
    setState(() {
      _englishOutput = result.output;
      _structureNote = result.structureNote;
    });
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
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'ISL Live',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Consumer<SignClassifierService>(
                    builder: (_, svc, __) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: svc.isReady
                            ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: svc.isReady ? const Color(0xFF4CAF50) : Colors.orange,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        svc.isReady ? '● Model Ready' : '○ Loading...',
                        style: TextStyle(
                          color: svc.isReady ? const Color(0xFF4CAF50) : Colors.orange,
                          fontSize: 11,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _cameraReady && _camera != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(_camera!),

                            // Current sign overlay at bottom of camera
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [Colors.black87, Colors.transparent],
                                  ),
                                ),
                                child: Consumer<SignClassifierService>(
                                  builder: (_, svc, __) => Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        svc.currentSign ?? 'Waiting for sign...',
                                        style: TextStyle(
                                          color: svc.currentSign != null
                                              ? Colors.white
                                              : Colors.white54,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      if (svc.currentSign != null) ...[
                                        const SizedBox(width: 12),
                                        // Confidence bar
                                        SizedBox(
                                          width: 60,
                                          child: LinearProgressIndicator(
                                            value: svc.currentConfidence,
                                            color: const Color(0xFF6B5CE7),
                                            backgroundColor: Colors.white24,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${(svc.currentConfidence * 100).toInt()}%',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Color(0xFF6B5CE7)),
                              SizedBox(height: 12),
                              Text('Starting camera...',
                                  style: TextStyle(color: Colors.white54)),
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
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ISL GLOSS',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        // Undo button
                        GestureDetector(
                          onTap: _undoLast,
                          child: const Text(
                            'Undo',
                            style: TextStyle(
                              color: Color(0xFF6B5CE7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Scrollable chip row of detected signs
                    _glossBuffer.isEmpty
                        ? const Text(
                            'Start signing...',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          )
                        : Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _glossBuffer
                                .asMap()
                                .entries
                                .map((e) => _GlossChip(
                                      word: e.value,
                                      isLast:
                                          e.key == _glossBuffer.length - 1,
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
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: const Color(0xFF6B5CE7), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ENGLISH OUTPUT',
                        style: TextStyle(
                          color: Color(0xFF6B5CE7),
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _englishOutput,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_structureNote.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '(${ _structureNote})',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
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
                    child: ElevatedButton.icon(
                      onPressed: _glossBuffer.isNotEmpty ? _translate : null,
                      icon: const Text('🤟'),
                      label: const Text('Translate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B5CE7),
                        disabledBackgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: _clear,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small chip widget for each detected gloss word ────────────────────────────
class _GlossChip extends StatelessWidget {
  final String word;
  final bool isLast;
  const _GlossChip({required this.word, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLast
            ? const Color(0xFF6B5CE7).withValues(alpha: 0.25)
            : Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLast ? const Color(0xFF6B5CE7) : Colors.white12,
          width: isLast ? 1.5 : 0.5,
        ),
      ),
      child: Text(
        word,
        style: TextStyle(
          color: isLast ? Colors.white : Colors.white70,
          fontSize: 13,
          fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
