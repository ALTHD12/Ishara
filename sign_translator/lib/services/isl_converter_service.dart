import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

enum SentenceType { statement, yesNoQuestion, whQuestion, negative }

class ISLToken {
  final String gloss;
  final String role;
  final int colorHex;

  const ISLToken({
    required this.gloss,
    required this.role,
    required this.colorHex,
  });
}

class PipelineStep {
  final String title;
  final String result;
  
  const PipelineStep({
    required this.title,
    required this.result,
  });
}

class TranslationResult {
  final String output;
  final SentenceType sentenceType;
  final List<ISLToken> tokens;
  final String structureNote;
  final List<PipelineStep> pipelineSteps;

  const TranslationResult({
    required this.output,
    required this.sentenceType,
    required this.tokens,
    required this.structureNote,
    this.pipelineSteps = const [],
  });
}

// ─── Service ──────────────────────────────────────────────────────────────────

class ISLConverterService extends ChangeNotifier {
  TranslationResult? _result;
  TranslationResult? get result => _result;

  int _getColorForRole(String role) {
    switch (role) {
      case 'SUBJECT': return 0xFF4CAF50;
      case 'OBJECT': return 0xFFFF6B6B;
      case 'VERB': return 0xFF6B5CE7;
      case 'TIME': return 0xFF2196F3;
      case 'WH-WORD': return 0xFF9C27B0;
      case 'NEGATION': return 0xFFFF9800;
      case 'YNQ-MARKER': return 0xFF888888;
      default: return 0xFF888888;
    }
  }

  // ── English → ISL ─────────────────────────────────────────────────────────
  Future<TranslationResult> englishToISL(String english) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendHttpUrl}/english-to-isl'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': english}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final tokensList = (data['tokens'] as List).map((t) {
          return ISLToken(
            gloss: t['gloss'],
            role: t['role'],
            colorHex: _getColorForRole(t['role']),
          );
        }).toList();

        final r = TranslationResult(
          output: data['output'],
          sentenceType: SentenceType.statement, // simplify for now
          tokens: tokensList,
          structureNote: data['note'] ?? 'Processed by NLP Backend',
        );
        _result = r;
        notifyListeners();
        return r;
      }
    } catch (e) {
      debugPrint('NLP Server Error: $e');
    }
    
    // Fallback if server is down
    final r = TranslationResult(
      output: english.toUpperCase(),
      sentenceType: SentenceType.statement,
      tokens: [],
      structureNote: 'Backend Error - returning raw input',
    );
    _result = r;
    notifyListeners();
    return r;
  }

  // ── ISL → English ─────────────────────────────────────────────────────────
  // Note: For now we'll just mock this or return raw until we implement the backend route
  Future<TranslationResult> islToEnglish(String gloss) async {
    final r = TranslationResult(
      output: gloss.toLowerCase(),
      sentenceType: SentenceType.statement,
      tokens: [],
      structureNote: 'ISL to English NLP pending backend implementation',
    );
    _result = r;
    notifyListeners();
    return r;
  }
}
