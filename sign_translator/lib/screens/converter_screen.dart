import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/isl_converter_service.dart';
import '../theme/app_themes.dart';
import '../widgets/neo_decorations.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  final _inputCtrl = TextEditingController();
  bool _englishToISL = true;
  TranslationResult? _result;

  void _convert() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final svc = context.read<ISLConverterService>();
    final res = _englishToISL
        ? await svc.englishToISL(text)
        : await svc.islToEnglish(text);
        
    if (mounted) {
      setState(() {
        _result = res;
      });
    }
  }

  void _setMode(bool englishToISL) {
    setState(() {
      _englishToISL = englishToISL;
      _result = null;
      _inputCtrl.clear();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 680;

    return Scaffold(
      body: DotGridBackground(
        dotColor: theme.colorScheme.outline,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────────────
                Text(
                  'ISL SEMANTIC CONVERTER',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CONVERT BETWEEN ENGLISH SENTENCES AND ISL GLOSS SYNTAX',
                  style: AppThemes.labelCaps(theme),
                ),
                const SizedBox(height: 24),

                // ── Main layout ───────────────────────────────────────────────
                isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildInputPanel(theme)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildOutputPanel(theme)),
                        ],
                      )
                    : Column(
                        children: [
                          _buildInputPanel(theme),
                          const SizedBox(height: 16),
                          _buildOutputPanel(theme),
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Left panel: mode toggle + text input + button ─────────────────────────
  Widget _buildInputPanel(ThemeData theme) {
    return NeoContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode toggle — neobrutalism boxy tabs
          Container(
            decoration: AppThemes.neoDecorationFlat(theme),
            child: Row(
              children: [
                _ModeTab(
                  label: 'ENGLISH → ISL',
                  selected: _englishToISL,
                  onTap: () => _setMode(true),
                ),
                Container(
                  width: AppThemes.borderWidth,
                  height: 40,
                  color: theme.colorScheme.outline,
                ),
                _ModeTab(
                  label: 'ISL → ENGLISH',
                  selected: !_englishToISL,
                  onTap: () => _setMode(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Input label
          Text(
            _englishToISL ? 'ENGLISH SENTENCE INPUT' : 'ISL GLOSS INPUT',
            style: AppThemes.labelCaps(theme),
          ),
          const SizedBox(height: 8),

          // Text field — neobrutalism
          Container(
            decoration: BoxDecoration(
              boxShadow: AppThemes.neoShadow(theme),
            ),
            child: TextField(
              controller: _inputCtrl,
              maxLength: 200,
              maxLines: 4,
              onSubmitted: (_) => _convert(),
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                counterStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
                hintText: _englishToISL
                    ? 'E.G. CAN YOU HELP ME?'
                    : 'E.G. YOU ME HELP',
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Convert button — neobrutalism
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: AppThemes.neoShadow(theme),
              ),
              child: ElevatedButton(
                onPressed: _convert,
                child: Text(
                  _englishToISL ? '🤟  CONVERT TO ISL' : '🤟  CONVERT TO ENGLISH',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Right panel: output card + token analysis ─────────────────────────────
  Widget _buildOutputPanel(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Output card — neobrutalism bordered
        NeoContainer(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _englishToISL
                        ? 'ISL GLOSS OUTPUT'
                        : 'ENGLISH SENTENCE OUTPUT',
                    style: AppThemes.labelCaps(theme).copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (_result != null)
                    _CopyButton(text: _result!.output),
                ],
              ),
              const SizedBox(height: 18),

              // Main output text
              Text(
                _result?.output ?? '—',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: theme.colorScheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),

              if (_result != null) ...[
                const SizedBox(height: 8),
                Text(
                  '(${_result!.structureNote})',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Token analysis panel
        if (_result != null) ...[
          const SizedBox(height: 14),
          NeoContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _englishToISL
                      ? 'ISL STRUCTURE ANALYSIS'
                      : 'ISL TOKEN ANALYSIS',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 14),
                ..._result!.tokens.map((token) => _buildTokenRow(token, theme)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTokenRow(ISLToken token, ThemeData theme) {
    final color = Color(token.colorHex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Coloured left bar
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              token.gloss.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color, width: 2),
            ),
            child: Text(
              token.role,
              style: TextStyle(
                fontFamily: 'Inter',
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.onSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppThemes.cornerRadius - 2),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              color: selected ? theme.colorScheme.surface : theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  final String text;
  const _CopyButton({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('COPIED TO CLIPBOARD'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: AppThemes.neoBorder(theme),
          borderRadius: BorderRadius.circular(AppThemes.cornerRadius),
        ),
        child: Text(
          'COPY',
          style: TextStyle(
            fontFamily: 'Inter',
            color: theme.colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}
