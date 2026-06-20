import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/isl_converter_service.dart';
import '../widgets/output_card.dart';

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

    final int durationMs = (2500 / _playbackSpeed).round();
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

  void _toggleSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else if (_playbackSpeed == 2.0) {
        _playbackSpeed = 0.5;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    
    // Restart timer with new speed if playing
    if (_isPlaying) {
      _playAnimation();
    }
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person, size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Avatar Animation Area',
                            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Subtitle Bar (Current word)
                  Container(
                    width: double.infinity,
                    height: 50,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        _currentSequence.isNotEmpty ? _currentSequence[_currentIndex] : '',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Animation Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filledTonal(
                        onPressed: _currentSequence.isNotEmpty ? _reloadAnimation : null,
                        icon: const Icon(Icons.replay),
                        tooltip: 'Replay',
                        iconSize: 28,
                      ),
                      FloatingActionButton(
                        onPressed: _currentSequence.isNotEmpty
                            ? () {
                                if (_isPlaying) {
                                  _pauseAnimation();
                                } else {
                                  _playAnimation();
                                }
                              }
                            : null,
                        elevation: 0,
                        backgroundColor: _currentSequence.isNotEmpty
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                        child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 32),
                      ),
                      InkWell(
                        onTap: _toggleSpeed,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_playbackSpeed}x',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            ),
            style: const TextStyle(fontSize: 18),
            onSubmitted: (_) => _translate(),
          ),
          const SizedBox(height: 16),
          
          // Translate Button
          FilledButton(
            onPressed: _translate,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Translate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
