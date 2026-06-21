import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/isl_converter_service.dart';
import '../widgets/output_card.dart';
import '../widgets/sign_avatar_painter.dart';
import '../theme/app_themes.dart';

class EnglishToISLScreen extends StatefulWidget {
  const EnglishToISLScreen({super.key});

  @override
  State<EnglishToISLScreen> createState() => _EnglishToISLScreenState();
}

class _EnglishToISLScreenState extends State<EnglishToISLScreen> {
  final TextEditingController _textController = TextEditingController();
  List<String> _currentSequence = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _animationTimer;
  double _playbackSpeed = 1.0;
  bool _isSpeedMenuExpanded = false;
  String _originalSentence = '';

  @override
  void dispose() {
    _animationTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _translate() async {
    if (_textController.text.trim().isEmpty) return;
    
    final converter = context.read<ISLConverterService>();
    final result = await converter.englishToISL(_textController.text);
    
    if (mounted) {
      setState(() {
        _originalSentence = _textController.text;
        _currentSequence = result.output.split(' ').where((w) => w.isNotEmpty).toList();
        _currentIndex = 0;
      });
      
      _playAnimation();
    }
  }

  void _playAnimation() {
    if (_currentSequence.isEmpty) return;
    
    _animationTimer?.cancel();
    setState(() {
      _isPlaying = true;
      if (_currentIndex >= _currentSequence.length) {
        _currentIndex = 0;
      }
    });

    final int durationMs = (1500 / _playbackSpeed).round(); // Default 1.5 secs per word
    _animationTimer = Timer.periodic(Duration(milliseconds: durationMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (_currentIndex < _currentSequence.length - 1) {
          _currentIndex++;
        } else {
          _isPlaying = false;
          timer.cancel();
        }
      });
    });
  }

  void _pauseAnimation() {
    _animationTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _reloadAnimation() {
    setState(() {
      _currentIndex = 0;
    });
    _playAnimation();
  }

  void _setSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
      _isSpeedMenuExpanded = false; // Auto-collapse on selection
    });
    
    if (_isPlaying) {
      _playAnimation();
    }
  }

  Widget _buildCircleButton({
    required Widget child,
    required VoidCallback? onPressed,
    bool isSelected = false,
    bool isPrimary = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(20),
        backgroundColor: isPrimary
            ? Theme.of(context).colorScheme.onSurface
            : isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: isPrimary
            ? Theme.of(context).scaffoldBackgroundColor
            : isSelected
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurfaceVariant,
        elevation: isPrimary ? 4 : 0,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Avatar Animation Panel
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Avatar placeholder
                  Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: SignAvatarPainter(theme: Theme.of(context)),
                          ),
                        ),
                        // TODO: switch to rive package for true skeletal sign animation
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Subtitle Bar (Current word)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                    ),
                    child: Center(
                      child: Text(
                        _currentSequence.isNotEmpty ? _currentSequence[_currentIndex] : '',
                        textAlign: TextAlign.center,
                        style: AppThemes.labelCaps(Theme.of(context)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Animation Controls (Expanding Pill)
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    crossFadeState: _isSpeedMenuExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCircleButton(
                          onPressed: _currentSequence.isNotEmpty ? _reloadAnimation : null,
                          child: const Icon(Icons.replay),
                        ),
                        _buildCircleButton(
                          onPressed: _currentSequence.isNotEmpty
                              ? () {
                                  if (_isPlaying) {
                                    _pauseAnimation();
                                  } else {
                                    _playAnimation();
                                  }
                                }
                              : null,
                          isPrimary: true,
                          child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 28),
                        ),
                        _buildCircleButton(
                          onPressed: () => setState(() => _isSpeedMenuExpanded = true),
                          child: Text('${_playbackSpeed}x', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ],
                    ),
                    secondChild: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => setState(() => _isSpeedMenuExpanded = false),
                              borderRadius: BorderRadius.circular(20),
                              child: const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Icon(Icons.circle, size: 12),
                              ),
                            ),
                            const SizedBox(width: 12),
                            for (final speed in [0.5, 0.75, 1.0, 1.5, 2.0]) ...[
                              InkWell(
                                onTap: () => _setSpeed(speed),
                                borderRadius: BorderRadius.circular(20),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _playbackSpeed == speed 
                                        ? Theme.of(context).colorScheme.onSurface 
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${speed}x',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: _playbackSpeed == speed
                                          ? Theme.of(context).colorScheme.surface
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sentence Input Box
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: 'Enter a sentence',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            ),
            style: const TextStyle(fontSize: 18),
            onSubmitted: (_) => _translate(),
          ),
          const SizedBox(height: 16),
          
          // Translate Button
          TextButton(
            onPressed: _translate,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
            ),
            child: Center(
              child: Text(
                'Translate',
                style: AppThemes.buttonLabel(Theme.of(context)),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Natural Language Output Card
          if (_originalSentence.isNotEmpty)
            OutputCard(
              title: 'Original Sentence',
              content: _originalSentence,
            ),
        ],
      ),
    );
  }
}
