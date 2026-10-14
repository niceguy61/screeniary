import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vtt_app/llm.dart';
import 'package:vtt_app/settings.dart';

AppSettings _with(String provider, void Function(ProviderConfig) fill) {
  final s = AppSettings();
  s.provider = provider;
  fill(s.active);
  return s;
}

String _header(Map<String, String> headers, String name) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
  }
  return '';
}

void main() {
  test('openai-compatible request shape carries vision image', () async {
    Map<String, dynamic>? seenBody;
    Map<String, String>? seenHeaders;
    String? seenUrl;
    final mock = MockClient((req) async {
      seenUrl = req.url.toString();
      seenHeaders = req.headers;
      seenBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'screen caption here'}
            }
          ]
        }),
        200,
      );
    });
    final client = LlmClient(httpClient: mock);
    final s = _with(Providers.openai, (c) {
      c.apiKey = 'sk-x';
      c.captionModel = 'gpt-4o-mini';
    });
    final out =
        await client.caption(s, Uint8List.fromList([1, 2, 3]));
    expect(out, 'screen caption here');
    expect(seenUrl, 'https://api.openai.com/v1/chat/completions');
    expect(_header(seenHeaders!, 'authorization'), 'Bearer sk-x');
    final content =
        (seenBody!['messages'] as List).first['content'] as List;
    final img = content.firstWhere((b) => b['type'] == 'image_url');
    expect(
      (img['image_url']['url'] as String).startsWith('data:image/png;base64,'),
      isTrue,
    );
    client.close();
  });

  test('openrouter adds referer headers', () async {
    Map<String, String>? seenHeaders;
    final mock = MockClient((req) async {
      seenHeaders = req.headers;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'ok'}
            }
          ]
        }),
        200,
      );
    });
    final client = LlmClient(httpClient: mock);
    final s = _with(Providers.openrouter, (c) {
      c.apiKey = 'sk-or';
      c.diaryModel = 'anthropic/claude-3.5-sonnet';
    });
    await client.diary(s, 'log');
    expect(_header(seenHeaders!, 'http-referer').isNotEmpty, isTrue);
    expect(_header(seenHeaders!, 'x-title'), 'VTT');
    client.close();
  });

  test('anthropic request shape and text parse', () async {
    Map<String, dynamic>? seenBody;
    Map<String, String>? seenHeaders;
    final mock = MockClient((req) async {
      seenHeaders = req.headers;
      seenBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'hello'},
            {'type': 'tool_use', 'id': 'x'},
          ]
        }),
        200,
      );
    });
    final client = LlmClient(httpClient: mock);
    final s = _with(Providers.anthropic, (c) {
      c.apiKey = 'sk-ant';
      c.diaryModel = 'claude-3-5-sonnet-20241022';
    });
    final out = await client.diary(s, 'log');
    expect(out, 'hello');
    expect(_header(seenHeaders!, 'x-api-key'), 'sk-ant');
    expect(_header(seenHeaders!, 'anthropic-version'), '2023-06-01');
    final content =
        (seenBody!['messages'] as List).first['content'] as List;
    expect(
      content.any((b) =>
          b['type'] == 'image' &&
          b['source']['type'] == 'base64'),
      isFalse, // text-only diary sends no image blocks
    );
    client.close();
  });

  test('bedrock auth header is well-formed and deterministic', () {
    Map<String, String> sign(String secret) => bedrockAuthHeaders(
          accessKey: 'AKID',
          secretKey: secret,
          region: 'us-east-1',
          modelId: 'amazon.nova-lite-v1:0',
          body: '{}',
          now: DateTime.utc(2024, 1, 1, 12, 0, 0),
        );
    final h1 = sign('secret');
    final h2 = sign('secret');
    expect(h1['Authorization'], h2['Authorization']);
    expect(
      h1['Authorization']!,
      startsWith(
        'AWS4-HMAC-SHA256 Credential=AKID/20240101/us-east-1/bedrock/aws4_request, '
        'SignedHeaders=content-type;host;x-amz-date, Signature=',
      ),
    );
    expect(h1['X-Amz-Date'], '20240101T120000Z');
    expect(
      sign('other')['Authorization'],
      isNot(equals(h1['Authorization'])),
    );
  });

  test('bedrock routing signs request and parses converse output',
      () async {
    Map<String, String>? seenHeaders;
    String? seenUrl;
    final mock = MockClient((req) async {
      seenHeaders = req.headers;
      seenUrl = req.url.toString();
      return http.Response(
        jsonEncode({
          'output': {
            'message': {
              'content': [
                {'text': 'diary text'}
              ]
            }
          }
        }),
        200,
      );
    });
    final client = LlmClient(httpClient: mock);
    final s = _with(Providers.bedrock, (c) {
      c.awsAccessKey = 'AKID';
      c.awsSecretKey = 'secret';
      c.region = 'us-east-1';
      c.diaryModel = 'amazon.nova-lite-v1:0';
    });
    final out = await client.diary(s, 'log');
    expect(out, 'diary text');
    expect(
      _header(seenHeaders!, 'authorization')
          .startsWith('AWS4-HMAC-SHA256 Credential=AKID/'),
      isTrue,
    );
    expect(
      seenUrl,
      contains('/model/amazon.nova-lite-v1%3A0/converse'),
    );
    client.close();
  });

  test('missing key throws a clear error without network', () async {
    var called = false;
    final mock = MockClient((req) async {
      called = true;
      return http.Response('{}', 200);
    });
    final client = LlmClient(httpClient: mock);
    final s = _with(Providers.openai, (c) {});
    expect(
      () => client.probe(s),
      throwsA(predicate((Object e) => e.toString().contains('API key'))),
    );
    expect(called, isFalse);
    client.close();
  });

  test('non-200 surfaces status and snippet', () async {
    final mock = MockClient((req) async {
      return http.Response('{"error":"unauthorized key"}', 401);
    });
    final client = LlmClient(httpClient: mock);
    final s = _with(Providers.openai, (c) {
      c.apiKey = 'bad';
      c.diaryModel = 'gpt-4o';
    });
    expect(
      () => client.probe(s),
      throwsA(predicate((Object e) => e.toString().contains('401'))),
    );
    client.close();
  });
}
