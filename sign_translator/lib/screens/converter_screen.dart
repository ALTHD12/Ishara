import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/isl_converter_service.dart';

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
    final isWide = MediaQuery.of(context).size.width > 680;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────────
              const Text(
                'ISL Semantic Converter',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Convert between English sentences and ISL Gloss syntax structure',
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const SizedBox(height: 24),

              // ── Main layout ───────────────────────────────────────────────
              isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildInputPanel()),
                        const SizedBox(width: 20),
                        Expanded(child: _buildOutputPanel()),
                      ],
                    )
                  : Column(
                      children: [
                        _buildInputPanel(),
                        const SizedBox(height: 16),
                        _buildOutputPanel(),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Left panel: mode toggle + text input + button ─────────────────────────
  Widget _buildInputPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode toggle tabs
          Container(
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _ModeTab(
                  label: 'English → ISL',
                  selected: _englishToISL,
                  onTap: () => _setMode(true),
                ),
                _ModeTab(
                  label: 'ISL → English',
                  selected: !_englishToISL,
                  onTap: () => _setMode(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Input label
          Text(
            _englishToISL ? 'English Sentence Input' : 'ISL Gloss Input',
            style: TextStyle(color: Colors.grey[300], fontSize: 13),
          ),
          const SizedBox(height: 8),

          // Text field
          TextField(
            controller: _inputCtrl,
            maxLength: 200,
            maxLines: 4,
            onSubmitted: (_) => _convert(),
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              counterStyle: TextStyle(color: Colors.grey[600]),
              hintText: _englishToISL
                  ? 'e.g. Can you help me?'
                  : 'e.g. YOU ME HELP',
              hintStyle: TextStyle(color: Colors.grey[700]),
              filled: true,
              fillColor: Colors.black26,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF6B5CE7), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Convert button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _convert,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B5CE7),
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
              child: Text(
                _englishToISL ? '🤟  Convert to ISL' : '🤟  Convert to English',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Right panel: output card + token analysis ─────────────────────────────
  Widget _buildOutputPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Output card (the big bordered box from screenshots)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF6B5CE7),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _englishToISL
                        ? 'ISL GLOSS OUTPUT'
                        : 'ENGLISH SENTENCE OUTPUT',
                    style: const TextStyle(
                      color: Color(0xFF6B5CE7),
                      fontSize: 11,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),

              if (_result != null) ...[
                const SizedBox(height: 8),
                Text(
                  '(${_result!.structureNote})',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Token analysis panel
        if (_result != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _englishToISL
                      ? 'ISL Structure Analysis'
                      : 'ISL Token Analysis',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ..._result!.tokens.map(_buildTokenRow),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTokenRow(ISLToken token) {
    final color = Color(token.colorHex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Coloured left bar (matches the design in screenshots)
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              token.gloss,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            token.role,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF6B5CE7) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey[500],
              fontSize: 13,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
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
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Copy',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ),
    );
  }
}
