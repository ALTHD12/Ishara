import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sign_classifier_service.dart';
import '../theme/app_themes.dart';

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
      ResolutionPreset.medium,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Training Mode'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Exact same Camera Feed box as ISLToEnglishScreen
              Container(
                height: 400,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
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
                        const Center(
                          child: CircularProgressIndicator(),
                        ),
                      
                      // Recording Status Overlay (Giant text)
                      Positioned.fill(
                        child: Consumer<SignClassifierService>(
                          builder: (context, classifier, child) {
                            if (classifier.recordingStatus.isEmpty) return const SizedBox.shrink();
                            
                            Color statusColor = Colors.orangeAccent;
                            if (classifier.recordingStatus.contains("RECORDING")) {
                              statusColor = Colors.redAccent;
                            } else if (classifier.recordingStatus.contains("Relax") || classifier.recordingStatus.contains("Saved")) {
                              statusColor = Colors.greenAccent;
                            }
                            
                            return Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  classifier.recordingStatus,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // Camera flip button
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: FloatingActionButton(
                          mini: true,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.8),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          onPressed: _switchCamera,
                          child: const Icon(Icons.flip_camera_ios),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Input Field
              TextField(
                controller: _labelController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Sign Label (e.g., HELLO)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  prefixIcon: const Icon(Icons.label_outline),
                ),
              ),
              
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _startRecording,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text('Record & Save Word', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _trainModel,
                      icon: const Icon(Icons.model_training),
                      label: const Text('Train Dictionary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Instructions:\n'
                    '1. Type the sign you want to add to the AI Dictionary.\n'
                    '2. Press "Record & Save Word". You will have a 3-second countdown.\n'
                    '3. Perform the sign. It will automatically save as a new dataset file.\n'
                    '4. Repeat for other words. (Requires at least 2 words in the dictionary).\n'
                    '5. Press "Train Dictionary" to train the AI on all saved words.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
