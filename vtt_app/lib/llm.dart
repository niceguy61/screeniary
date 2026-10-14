import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'ollama.dart';
import 'settings.dart';

const captionPrompt =
    '이 컴퓨터 화면 스크린샷을 한국어로 한 줄(50자 이내)로 설명해줘. '
    '예: "크롬에서 Flutter 문서 읽는 중". 설명 문장만 출력해.';

String diaryPromptFor(String log) =>
    '아래는 오늘 컴퓨터 사용 기록이다. 한국어로 (1) 3줄 일기 요약, '
    '(2) 오늘 한 일 불릿 3~5개를 써줘.\n\n$log';

// ---------- OpenAI-compatible (OpenAI + OpenRouter) ----------

Map<String, dynamic> openAiBody({
  required String model,
  required String prompt,
  required List<String> imagesB64,
  int maxTokens = 1000,
}) {
  final content = <Map<String, dynamic>>[
    {'type': 'text', 'text': prompt},
  ];
  for (final b64 in imagesB64) {
    content.add({
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,$b64'},
    });
  }
  return {
    'model': model,
    'temperature': 0.2,
    'max_tokens': maxTokens,
    'messages': [
      {'role': 'user', 'content': content},
    ],
  };
}

String openAiText(Map<String, dynamic> res) {
  final choices = res['choices'] as List<dynamic>? ?? [];
  if (choices.isEmpty) return '';
  final msg = (choices.first as Map<String, dynamic>)['message'];
  if (msg is! Map<String, dynamic>) return '';
  final c = msg['content'];
  if (c is String) return c.trim();
  if (c is List) {
    return [
      for (final b in c)
        if (b is Map<String, dynamic> && b['text'] is String)
          (b['text'] as String),
    ].join('\n').trim();
  }
  return '';
}

// ---------- Anthropic ----------

Map<String, dynamic> anthropicBody({
  required String model,
  required String prompt,
  required List<String> imagesB64,
  int maxTokens = 1000,
}) {
  final content = <Map<String, dynamic>>[
    {'type': 'text', 'text': prompt},
  ];
  for (final b64 in imagesB64) {
    content.add({
      'type': 'image',
      'source': {'type': 'base64', 'media_type': 'image/png', 'data': b64},
    });
  }
  return {
    'model': model,
    'max_tokens': maxTokens,
    'messages': [
      {'role': 'user', 'content': content},
    ],
  };
}

Map<String, String> anthropicHeaders(String apiKey) => {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };

String anthropicText(Map<String, dynamic> res) {
  final content = res['content'] as List<dynamic>? ?? [];
  return [
    for (final b in content)
      if (b is Map<String, dynamic> &&
          b['type'] == 'text' &&
          b['text'] is String)
        (b['text'] as String),
  ].join('\n').trim();
}

// ---------- AWS Bedrock (Converse API, SigV4) ----------

String _two(int n) => n.toString().padLeft(2, '0');

Map<String, String> bedrockAuthHeaders({
  required String accessKey,
  required String secretKey,
  required String region,
  required String modelId,
  required String body,
  required DateTime now,
}) {
  final t = now.toUtc();
  final amzDate =
      '${t.year}${_two(t.month)}${_two(t.day)}T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
  final dateStamp = '${t.year}${_two(t.month)}${_two(t.day)}';
  final host = 'bedrock-runtime.$region.amazonaws.com';
  final path = '/model/${Uri.encodeComponent(modelId)}/converse';
  final payloadHash = sha256.convert(utf8.encode(body)).toString();
  const signedHeaders = 'content-type;host;x-amz-date';
  final canonicalHeaders =
      'content-type:application/json\nhost:$host\nx-amz-date:$amzDate\n';
  final canonicalRequest =
      'POST\n$path\n\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
  final scope = '$dateStamp/$region/bedrock/aws4_request';
  final stringToSign = 'AWS4-HMAC-SHA256\n'
      '$amzDate\n'
      '$scope\n'
      '${sha256.convert(utf8.encode(canonicalRequest))}';

  List<int> hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;
  final kDate = hmac(utf8.encode('AWS4$secretKey'), dateStamp);
  final kRegion = hmac(kDate, region);
  final kService = hmac(kRegion, 'bedrock');
  final kSigning = hmac(kService, 'aws4_request');
  final signature = Hmac(sha256, kSigning)
      .convert(utf8.encode(stringToSign))
      .toString();

  return {
    'Content-Type': 'application/json',
    'X-Amz-Date': amzDate,
    'Authorization': 'AWS4-HMAC-SHA256 '
        'Credential=$accessKey/$scope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature',
  };
}

Map<String, dynamic> bedrockBody({
  required String prompt,
  required List<String> imagesB64,
}) {
  final content = <Map<String, dynamic>>[
    {'text': prompt},
  ];
  for (final b64 in imagesB64) {
    content.add({
      'image': {
        'format': 'png',
        'source': {'bytes': b64},
      },
    });
  }
  return {
    'messages': [
      {'role': 'user', 'content': content},
    ],
  };
}

String bedrockText(Map<String, dynamic> res) {
  final output = res['output'] as Map<String, dynamic>?;
  final message = output?['message'] as Map<String, dynamic>?;
  final content = message?['content'] as List<dynamic>? ?? [];
  return [
    for (final b in content)
      if (b is Map<String, dynamic> && b['text'] is String)
        (b['text'] as String),
  ].join('\n').trim();
}

// ---------- Google Gemini (generateContent) ----------

Map<String, dynamic> geminiBody({
  required String prompt,
  required List<String> imagesB64,
}) {
  final parts = <Map<String, dynamic>>[
    {'text': prompt},
  ];
  for (final b64 in imagesB64) {
    parts.add({
      'inline_data': {'mime_type': 'image/png', 'data': b64},
    });
  }
  return {
    'contents': [
      {'parts': parts},
    ],
    'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 1000},
  };
}

String geminiText(Map<String, dynamic> res) {
  final cands = res['candidates'] as List<dynamic>? ?? [];
  if (cands.isEmpty) {
    final fb = res['promptFeedback'] as Map<String, dynamic>?;
    throw Exception('Gemini 차단됨: ${fb?['blockReason'] ?? 'unknown'}');
  }
  final content =
      (cands.first as Map<String, dynamic>)['content']
          as Map<String, dynamic>?;
  final parts = content?['parts'] as List<dynamic>? ?? [];
  return [
    for (final b in parts)
      if (b is Map<String, dynamic> && b['text'] is String)
        (b['text'] as String),
  ].join('\n').trim();
}

// ---------- Unified client ----------

class LlmClient {
  final http.Client httpClient;
  final Ollama ollama;

  LlmClient({http.Client? httpClient, Ollama? ollama})
      : httpClient = httpClient ?? http.Client(),
        ollama = ollama ?? Ollama();

  void close() {
    httpClient.close();
    ollama.close();
  }

  Future<String> caption(AppSettings s, Uint8List imageBytes) {
    final b64 = base64Encode(imageBytes);
    return _complete(
      s,
      caption: true,
      prompt: captionPrompt,
      imagesB64: [b64],
      timeout: const Duration(seconds: 180),
    );
  }

  Future<String> diary(AppSettings s, String log) => _complete(
        s,
        caption: false,
        prompt: diaryPromptFor(log),
        imagesB64: const [],
        timeout: const Duration(seconds: 300),
      );

  Future<String> probe(AppSettings s) => _complete(
        s,
        caption: false,
        prompt: 'Reply with exactly: ok',
        imagesB64: const [],
        timeout: const Duration(seconds: 90),
      );

  Future<String> _complete(
    AppSettings s, {
    required bool caption,
    required String prompt,
    required List<String> imagesB64,
    required Duration timeout,
  }) async {
    final cfg = s.active;
    switch (s.provider) {
      case Providers.ollama:
        final model = (caption ? cfg.captionModel : cfg.diaryModel).isEmpty
            ? (caption ? Ollama.captionModel : Ollama.diaryModel)
            : (caption ? cfg.captionModel : cfg.diaryModel);
        return ollama.generate(
          model: model,
          prompt: prompt,
          images: imagesB64,
          timeout: timeout,
        );
      case Providers.openai:
      case Providers.openrouter:
        return _openAiCompatible(
          s.provider,
          cfg,
          caption: caption,
          prompt: prompt,
          imagesB64: imagesB64,
          timeout: timeout,
        );
      case Providers.anthropic:
        return _anthropic(
          cfg,
          caption: caption,
          prompt: prompt,
          imagesB64: imagesB64,
          timeout: timeout,
        );
      case Providers.bedrock:
        return _bedrock(
          cfg,
          caption: caption,
          prompt: prompt,
          imagesB64: imagesB64,
          timeout: timeout,
        );
      case Providers.gemini:
        return _gemini(
          cfg,
          caption: caption,
          prompt: prompt,
          imagesB64: imagesB64,
          timeout: timeout,
        );
      default:
        throw Exception('unknown provider ${s.provider}');
    }
  }

  Future<String> _postJson(
    Uri url,
    Map<String, String> headers,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    final r = await httpClient
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
    if (r.statusCode != 200) {
      final snippet =
          r.body.length > 300 ? '${r.body.substring(0, 300)}…' : r.body;
      throw Exception('HTTP ${r.statusCode}: $snippet');
    }
    return r.body;
  }

  Future<String> _openAiCompatible(
    String provider,
    ProviderConfig cfg, {
    required bool caption,
    required String prompt,
    required List<String> imagesB64,
    required Duration timeout,
  }) async {
    if (cfg.apiKey.isEmpty) throw Exception('API key가 비어 있음');
    final model = caption ? cfg.captionModel : cfg.diaryModel;
    if (model.isEmpty) throw Exception('모델명이 비어 있음');
    final base = cfg.baseUrl.isEmpty
        ? (provider == Providers.openrouter
            ? 'https://openrouter.ai/api/v1'
            : 'https://api.openai.com/v1')
        : cfg.baseUrl;
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${cfg.apiKey}',
      if (provider == Providers.openrouter)
        'HTTP-Referer': 'https://localhost/vtt',
      if (provider == Providers.openrouter) 'X-Title': 'VTT',
    };
    final raw = await _postJson(
      Uri.parse('$base/chat/completions'),
      headers,
      openAiBody(model: model, prompt: prompt, imagesB64: imagesB64),
      timeout,
    );
    return openAiText(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String> _anthropic(
    ProviderConfig cfg, {
    required bool caption,
    required String prompt,
    required List<String> imagesB64,
    required Duration timeout,
  }) async {
    if (cfg.apiKey.isEmpty) throw Exception('API key가 비어 있음');
    final model = caption ? cfg.captionModel : cfg.diaryModel;
    if (model.isEmpty) throw Exception('모델명이 비어 있음');
    final raw = await _postJson(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      anthropicHeaders(cfg.apiKey),
      anthropicBody(model: model, prompt: prompt, imagesB64: imagesB64),
      timeout,
    );
    return anthropicText(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String> _gemini(
    ProviderConfig cfg, {
    required bool caption,
    required String prompt,
    required List<String> imagesB64,
    required Duration timeout,
  }) async {
    if (cfg.apiKey.isEmpty) throw Exception('API key가 비어 있음');
    final model = caption ? cfg.captionModel : cfg.diaryModel;
    if (model.isEmpty) throw Exception('모델명이 비어 있음');
    final raw = await _postJson(
      Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
      {
        'Content-Type': 'application/json',
        'x-goog-api-key': cfg.apiKey,
      },
      geminiBody(prompt: prompt, imagesB64: imagesB64),
      timeout,
    );
    return geminiText(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String> _bedrock(
    ProviderConfig cfg, {
    required bool caption,
    required String prompt,
    required List<String> imagesB64,
    required Duration timeout,
  }) async {
    if (cfg.awsAccessKey.isEmpty || cfg.awsSecretKey.isEmpty) {
      throw Exception('AWS 키가 비어 있음');
    }
    final model = caption ? cfg.captionModel : cfg.diaryModel;
    if (model.isEmpty) throw Exception('모델 ID가 비어 있음');
    final body = jsonEncode(bedrockBody(prompt: prompt, imagesB64: imagesB64));
    final headers = bedrockAuthHeaders(
      accessKey: cfg.awsAccessKey,
      secretKey: cfg.awsSecretKey,
      region: cfg.region.isEmpty ? 'us-east-1' : cfg.region,
      modelId: model,
      body: body,
      now: DateTime.now(),
    );
    final host =
        'bedrock-runtime.${cfg.region.isEmpty ? 'us-east-1' : cfg.region}.amazonaws.com';
    final r = await httpClient
        .post(
          Uri.parse(
              'https://$host/model/${Uri.encodeComponent(model)}/converse'),
          headers: headers,
          body: body,
        )
        .timeout(timeout);
    if (r.statusCode != 200) {
      final snippet =
          r.body.length > 300 ? '${r.body.substring(0, 300)}…' : r.body;
      throw Exception('Bedrock ${r.statusCode}: $snippet');
    }
    return bedrockText(jsonDecode(r.body) as Map<String, dynamic>);
  }
}
