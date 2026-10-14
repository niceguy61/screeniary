import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vtt_app/update.dart';

void main() {
  test('compareVersions orders dotted versions', () {
    expect(compareVersions('0.5.9', 'v0.5.10'), -1);
    expect(compareVersions('0.5.10', '0.5.10'), 0);
    expect(compareVersions('0.6.0', '0.5.10'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('10.0.0', '9.9.9'), 1);
  });

  test('newer release is reported available', () async {
    final mock = MockClient((req) async {
      return http.Response('{"tag_name":"v9.9.9"}', 200);
    });
    final res =
        await checkForUpdate(current: '0.5.10', client: mock);
    expect(res.checked, isTrue);
    expect(res.available, isTrue);
    expect(res.latest, 'v9.9.9');
  });

  test('same version means up to date', () async {
    final mock = MockClient((req) async {
      return http.Response('{"tag_name":"v0.5.10"}', 200);
    });
    final res =
        await checkForUpdate(current: '0.5.10', client: mock);
    expect(res.checked, isTrue);
    expect(res.available, isFalse);
  });

  test('404 on latest falls back to tags', () async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/releases/latest')) {
        return http.Response('{"message":"Not Found"}', 404);
      }
      return http.Response(
        jsonEncode([
          {'name': 'v0.5.9'},
          {'name': 'v0.5.10'},
        ]),
        200,
      );
    });
    final res =
        await checkForUpdate(current: '0.5.9', client: mock);
    expect(res.checked, isTrue);
    expect(res.available, isTrue);
    expect(res.latest, 'v0.5.10');
  });

  test('empty tags means no releases published yet', () async {
    final mock = MockClient((req) async {
      if (req.url.path.endsWith('/releases/latest')) {
        return http.Response('{"message":"Not Found"}', 404);
      }
      return http.Response('[]', 200);
    });
    final res =
        await checkForUpdate(current: '0.5.10', client: mock);
    expect(res.checked, isFalse);
    expect(res.available, isFalse);
  });
}
