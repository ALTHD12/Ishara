import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/isl_converter_service.dart';
import '../widgets/output_card.dart';
import '../widgets/signing_playback_widget.dart';
import '../widgets/neo_decorations.dart';
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

  // Quick suggestion chips
  static const _suggestions = ['Help me', 'Where is it?', 'Thank you'];

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
    
    setState(() {
      _isPlaying = true;
      if (_currentIndex >= _currentSequence.length) {
        _currentIndex = 0;
      }
    });
  }

  void _onWordComplete() async {
    if (!mounted || !_isPlaying) return;
    
    // Pause for a moment between words so it feels natural
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || !_isPlaying) return;

    setState(() {
      if (_currentIndex < _currentSequence.length - 1) {
        _currentIndex++;
      } else {
        _isPlaying = false;
      }
    });
  }

  void _pauseAnimation() {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ══════════════════════════════════════════════════════════════
          // Gloss sequence pill — bordered, active word in yellow
          // ══════════════════════════════════════════════════════════════
          if (_currentSequence.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: AppThemes.neoDecorationFlat(theme),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _currentSequence.asMap().entries.map((entry) {
                  final isActive = entry.key == _currentIndex;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.key > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '·',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFFFFD600) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.value.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1.0,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ══════════════════════════════════════════════════════════════
          // Avatar Animation Panel — neobrutalism card
          // ══════════════════════════════════════════════════════════════
          NeoContainer(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Avatar viewport
                Container(
                  height: 250,
                  width: double.infinity,
                  decoration: AppThemes.neoDecorationFlat(theme),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SigningPlaybackWidget(
                          sequenceAsset: 'assets/recordings/${_currentSequence.isNotEmpty ? _currentSequence[_currentIndex] : "HELLO"}.bytes',
                          isPlaying: _isPlaying,
                          speed: _playbackSpeed,
                          onComplete: _onWordComplete,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Current word subtitle
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: AppThemes.neoDecorationFlat(theme),
                  child: Center(
                    child: Text(
                      _currentSequence.isNotEmpty ? _currentSequence[_currentIndex].toUpperCase() : '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // ══════════════════════════════════════════════════════════
                // Transport controls — neobrutalism styled
                // ══════════════════════════════════════════════════════════
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 300),
                  crossFadeState: _isSpeedMenuExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: AppThemes.neoDecorationFlat(theme),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Restart
                        _buildControlButton(
                          icon: Icons.skip_previous,
                          onTap: _currentSequence.isNotEmpty ? _reloadAnimation : null,
                          theme: theme,
                        ),
                        const SizedBox(width: 8),
                        // Replay
                        _buildControlButton(
                          icon: Icons.replay,
                          onTap: _currentSequence.isNotEmpty ? _reloadAnimation : null,
                          theme: theme,
                        ),
                        const SizedBox(width: 12),
                        // PLAY — big circle, filled black, white icon
                        GestureDetector(
                          onTap: _currentSequence.isNotEmpty
                              ? () {
                                  if (_isPlaying) {
                                    _pauseAnimation();
                                  } else {
                                    _playAnimation();
                                  }
                                }
                              : null,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.outline,
                                width: AppThemes.borderWidth,
                              ),
                              boxShadow: AppThemes.neoShadow(theme),
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: theme.colorScheme.surface,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Fast forward
                        _buildControlButton(
                          icon: Icons.skip_next,
                          onTap: _currentSequence.isNotEmpty
                              ? () {
                                  if (_currentIndex < _currentSequence.length - 1) {
                                    setState(() => _currentIndex++);
                                  }
                                }
                              : null,
                          theme: theme,
                        ),
                        const SizedBox(width: 8),
                        // Speed chip
                        GestureDetector(
                          onTap: () => setState(() => _isSpeedMenuExpanded = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                              border: AppThemes.neoBorder(theme),
                            ),
                            child: Text(
                              '${_playbackSpeed}x',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  secondChild: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: AppThemes.neoDecorationFlat(theme),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _isSpeedMenuExpanded = false),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          for (final speed in [0.5, 0.75, 1.0, 1.5, 2.0]) ...[
                            GestureDetector(
                              onTap: () => _setSpeed(speed),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _playbackSpeed == speed 
                                      ? theme.colorScheme.onSurface 
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
                                  border: _playbackSpeed == speed
                                      ? AppThemes.neoBorder(theme)
                                      : null,
                                ),
                                child: Text(
                                  '${speed}x',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: _playbackSpeed == speed
                                        ? theme.colorScheme.surface
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ]
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ══════════════════════════════════════════════════════════════
          // Text Input — neobrutalism styled
          // ══════════════════════════════════════════════════════════════
          Container(
            decoration: BoxDecoration(
              boxShadow: AppThemes.neoShadow(theme),
            ),
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'ENTER A SENTENCE...',
              ),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              onSubmitted: (_) => _translate(),
            ),
          ),
          const SizedBox(height: 16),
          
          // ══════════════════════════════════════════════════════════════
          // "TRANSLATE" tap target — bold text, no button background
          // ══════════════════════════════════════════════════════════════
          GestureDetector(
            onTap: _translate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'TRANSLATE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ══════════════════════════════════════════════════════════════
          // Quick suggestion chips
          // ══════════════════════════════════════════════════════════════
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions.map((suggestion) {
              return GestureDetector(
                onTap: () {
                  _textController.text = suggestion;
                  _translate();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: AppThemes.neoDecoration(theme),
                  child: Text(
                    suggestion.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.8,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            }).toList(),
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

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onTap,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
          border: AppThemes.neoBorder(theme),
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap != null
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
