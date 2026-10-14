import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Minimal Ollama client (localhost). Text + vision, stream:false only.
/// Calls are sequential by design - never load VLM and LLM at once on 12GB.
class Ollama {
  static const host = 'http://127.0.0.1:11434';
  static const captionModel = 'qwen2.5vl:3b';
  static const diaryModel = 'qwen3:8b';

  final http.Client _client;

  Ollama({http.Client? client}) : _client = client ?? http.Client();

  Future<bool> alive() async {
    try {
      final r = await _client
          .get(Uri.parse('$host/api/tags'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> models() async {
    final r = await _client
        .get(Uri.parse('$host/api/tags'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      throw Exception('ollama tags: ${r.statusCode}');
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final list = body['models'] as List<dynamic>? ?? [];
    return [
      for (final m in list) (m as Map<String, dynamic>)['name'] as String,
    ];
  }

  Future<String> generate({
    required String model,
    required String prompt,
    List<String> images = const [],
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final r = await _client
        .post(
          Uri.parse('$host/api/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'prompt': prompt,
            'images': images,
            'stream': false,
            'options': {'temperature': 0.2},
          }),
        )
        .timeout(timeout);
    if (r.statusCode != 200) {
      throw Exception('ollama ${r.statusCode}: ${r.body}');
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['response'] as String?) ?? '').trim();
  }

  /// One-line Korean caption for a screenshot file.
  Future<String> caption(String imagePath) {
    return _captionFile(imagePath);
  }

  Future<String> _captionFile(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    return generate(
      model: captionModel,
      prompt: '이 컴퓨터 화면 스크린샷을 한국어로 한 줄(50자 이내)로 설명해줘. '
          '예: "크롬에서 Flutter 문서 읽는 중". 설명 문장만 출력해.',
      images: [base64Encode(bytes)],
      timeout: const Duration(seconds: 180),
    );
  }

  /// Daily diary from a plain-text activity log.
  Future<String> diary(String log) {
    return generate(
      model: diaryModel,
      prompt: '아래는 오늘 컴퓨터 사용 기록이다. 한국어로 (1) 3줄 일기 요약, '
          '(2) 오늘 한 일 불릿 3~5개를 써줘.\n\n$log',
      timeout: const Duration(seconds: 300),
    );
  }

  void close() => _client.close();
}
