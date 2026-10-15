import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';
import '../theme/app_themes.dart';
import '../widgets/neo_decorations.dart';
import '../widgets/connection_status_badge.dart';

class DataRecorderScreen extends StatefulWidget {
  const DataRecorderScreen({super.key});

  @override
  State<DataRecorderScreen> createState() => _DataRecorderScreenState();
}

class _DataRecorderScreenState extends State<DataRecorderScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  bool _cameraReady = false;
  CameraLensDirection _lensDirection = CameraLensDirection.front;

  final TextEditingController _labelController = TextEditingController();
  late SignClassifierService _classifierService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _classifierService = context.read<SignClassifierService>();
    _initCamera();
    
    // Ensure websocket is connected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_classifierService.isReady) {
        _classifierService.loadModels();
      }
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
      ResolutionPreset.low,
      enableAudio: false,
    );

    try {
      await _camera!.initialize();
      _camera!.startImageStream(_onFrame);
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('CAMERA ERROR: $e');
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
      await Future.delayed(const Duration(milliseconds: 300));
    }
    
    _lensDirection = _lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
        
    await _initCamera();
  }

  void _onFrame(CameraImage image) {
    if (!mounted) return;
    _classifierService.processFrame(
      image, 
      _camera!.description.sensorOrientation
    );
  }

  void _startRecording() {
    if (_labelController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a Sign Label')),
      );
      return;
    }
    
    _classifierService.startContinuousRecording(_labelController.text.trim());
  }

  void _trainModel() {
    _classifierService.triggerTraining();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Model Training Started in Background')),
    );
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
    _camera?.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('DATA TRAINING MODE'),
      ),
      body: DotGridBackground(
        dotColor: theme.colorScheme.outline,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Camera Feed — neobrutalism card with corner reticles
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
                                child: CameraPreview(_camera!),
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

                        // Corner reticles
                        Positioned.fill(
                          child: CustomPaint(
                            painter: CornerReticlesPainter(
                              color: Colors.white,
                              strokeWidth: 3.0,
                            ),
                          ),
                        ),
                        
                        // Recording Status Overlay
                        Positioned.fill(
                          child: Consumer<SignClassifierService>(
                            builder: (context, classifier, child) {
                              if (classifier.recordingStatus.isEmpty) return const SizedBox.shrink();
                              
                              Color statusColor = const Color(0xFFFFD600);
                              if (classifier.recordingStatus.contains("RECORDING")) {
                                statusColor = const Color(0xFFFF3B5C);
                              } else if (classifier.recordingStatus.contains("Relax") || classifier.recordingStatus.contains("Saved")) {
                                statusColor = const Color(0xFF4CAF50);
                              }
                              
                              return Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                                    border: Border.all(color: statusColor, width: AppThemes.borderWidth),
                                  ),
                                  child: Text(
                                    classifier.recordingStatus.toUpperCase(),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      color: statusColor,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        const Positioned(
                          bottom: 16,
                          left: 16,
                          child: ConnectionStatusBadge(),
                        ),

                        // Camera flip button — neobrutalism square
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
                              child: const Icon(
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
                
                // Input Field — neobrutalism
                Container(
                  decoration: BoxDecoration(
                    boxShadow: AppThemes.neoShadow(theme),
                  ),
                  child: TextField(
                    controller: _labelController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'SIGN LABEL (E.G., HELLO)',
                      prefixIcon: const Icon(Icons.label_outline),
                    ),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),

                // Action Buttons — neobrutalism
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: AppThemes.neoShadow(theme),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _startRecording,
                          icon: const Icon(Icons.fiber_manual_record),
                          label: const Text('RECORD & SAVE', style: TextStyle(fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3B5C),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: AppThemes.neoShadow(theme),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _trainModel,
                          icon: const Icon(Icons.model_training),
                          label: const Text('TRAIN MODEL', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                NeoContainer(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'INSTRUCTIONS:\n'
                    '1. TYPE THE SIGN YOU WANT TO ADD TO THE AI DICTIONARY.\n'
                    '2. PRESS "RECORD & SAVE". YOU WILL HAVE A 3-SECOND COUNTDOWN.\n'
                    '3. PERFORM THE SIGN. IT WILL AUTOMATICALLY SAVE AS A NEW DATASET FILE.\n'
                    '4. REPEAT FOR OTHER WORDS. (REQUIRES AT LEAST 2 WORDS IN THE DICTIONARY).\n'
                    '5. PRESS "TRAIN MODEL" TO TRAIN THE AI ON ALL SAVED WORDS.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
