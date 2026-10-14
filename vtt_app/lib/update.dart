import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const repoReleasesUrl =
    'https://github.com/niceguy61/screeniary/releases';
const _apiLatest =
    'https://api.github.com/niceguy61/screeniary/releases/latest';
const _apiTags =
    'https://api.github.com/niceguy61/screeniary/tags';

/// Compares dotted versions (leading `v` and `-suffix` ignored).
/// Returns -1 if a < b, 0 if equal, 1 if a > b.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceAll(RegExp(r'^[vV]'), '')
      .split('-')
      .first
      .split('.')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();
  final pa = parts(a);
  final pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

class UpdateCheck {
  /// false when the check itself failed (offline, no releases yet...).
  final bool checked;
  final bool available;
  final String latest;
  final String note;
  const UpdateCheck({
    required this.checked,
    required this.available,
    required this.latest,
    required this.note,
  });
}

/// Checks the latest GitHub release against [current].
///
/// Tries `/releases/latest` first, then falls back to the tag list
/// (brand-new repos can 404 on the releases endpoint for anonymous
/// callers while the data propagates).
Future<UpdateCheck> checkForUpdate({
  required String current,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(
      Uri.parse(_apiLatest),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final tag =
          (jsonDecode(r.body) as Map<String, dynamic>)['tag_name']
                  as String? ??
              '';
      if (tag.isEmpty) {
        return const UpdateCheck(
          checked: false,
          available: false,
          latest: '',
          note: '릴리즈 정보 파싱 실패',
        );
      }
      return _verdict(current, tag);
    }
    if (r.statusCode != 404) {
      return UpdateCheck(
        checked: false,
        available: false,
        latest: '',
        note: '확인 실패 (HTTP ${r.statusCode})',
      );
    }
    return await _checkViaTags(c, current);
  } on TimeoutException {
    return const UpdateCheck(
      checked: false,
      available: false,
      latest: '',
      note: '확인 실패 (시간 초과, 네트워크 확인)',
    );
  } catch (e) {
    return UpdateCheck(
      checked: false,
      available: false,
      latest: '',
      note: '확인 실패 ($e)',
    );
  } finally {
    if (client == null) c.close();
  }
}

UpdateCheck _verdict(String current, String tag) {
  final cmp = compareVersions(current, tag);
  return UpdateCheck(
    checked: true,
    available: cmp < 0,
    latest: tag,
    note: cmp < 0 ? '새 버전 $tag 사용 가능' : '최신 버전입니다 ($current)',
  );
}

Future<UpdateCheck> _checkViaTags(
    http.Client c, String current) async {
  try {
    final r = await c.get(
      Uri.parse(_apiTags),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      return const UpdateCheck(
        checked: false,
        available: false,
        latest: '',
        note: '릴리즈 정보 없음 (아직 배포된 릴리즈가 없습니다)',
      );
    }
    final tags = jsonDecode(r.body) as List<dynamic>;
    String best = '';
    for (final t in tags) {
      final name =
          (t as Map<String, dynamic>)['name'] as String? ?? '';
      if (name.isEmpty) continue;
      if (best.isEmpty || compareVersions(best, name) < 0) {
        best = name;
      }
    }
    if (best.isEmpty) {
      return const UpdateCheck(
        checked: false,
        available: false,
        latest: '',
        note: '릴리즈 정보 없음 (아직 배포된 릴리즈가 없습니다)',
      );
    }
    return _verdict(current, best);
  } catch (e) {
    return UpdateCheck(
      checked: false,
      available: false,
      latest: '',
      note: '확인 실패 ($e)',
    );
  }
}
