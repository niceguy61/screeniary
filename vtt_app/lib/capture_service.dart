import 'dart:async';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import 'db.dart';
import 'hash.dart';
import 'llm.dart';
import 'monitors.dart';
import 'screen_gdi.dart';
import 'settings.dart';

/// 10s-interval screen capture loop with aHash dedup.
/// Screenshots land in the `support`/shots folder, metadata in timeline.db.
class CaptureService extends ChangeNotifier {
  static const defaultInterval = Duration(seconds: 10);

  /// Hamming distance <= threshold counts as "same screen".
  static const dupThreshold = 3;

  final llm = LlmClient();
  AppSettings? _settings;

  bool running = false;
  int saved = 0;
  int skipped = 0;
  int captioned = 0;
  bool captionBusy = false;
  bool ollamaOk = false;
  String lastError = '';
  DateTime? lastTick;
  String lastResult = '대기 중';
  String scopeText = '전체 화면';
  String? _lastHash;
  Timer? _timer;

  Future<void> start() async {
    if (running) return;
    running = true;
    final s = await AppSettings.load();
    _settings = s;
    if (s.provider == Providers.ollama) {
      ollamaOk = await llm.ollama.alive();
      if (!ollamaOk) {
        lastError = 'Ollama 미연결(127.0.0.1:11434) - 캡션 없이 캡처만 저장';
      }
    } else {
      // Remote providers fail per-call with a clear message; no pre-check.
      ollamaOk = true;
    }
    notifyListeners();
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: s.captureIntervalSec),
      (_) => _tick(),
    );
    await _tick();
  }

  /// Re-read settings (call after the settings page saves).
  Future<void> reloadSettings() async {
    _settings = await AppSettings.load();
    notifyListeners();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    running = false;
    notifyListeners();
  }

  Future<void> captureOnce() => _tick();

  Future<void> _tick() async {
    try {
      final support = await getApplicationSupportDirectory();
      final shots = Directory(p.join(support.path, 'shots'));
      if (!await shots.exists()) {
        await shots.create(recursive: true);
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final target = p.join(shots.path, '$ts.png');

      final settings = _settings ?? await AppSettings.load();
      _settings = settings;
      final monitors = await listMonitors();
      if (monitors.isEmpty) {
        lastError = '화면 목록 조회 실패';
        _mark('캡처 실패');
        return;
      }
      MonitorRect? region =
          resolveRegion(monitors, settings.selectedMonitors);
      if (region == null) {
        // Saved selection matches nothing (e.g. unplugged monitor):
        // fall back to the primary monitor only — never silently
        // capture everything the user excluded.
        final primaries =
            monitors.where((m) => m.primary).toList();
        final fb =
            primaries.isNotEmpty ? primaries.first : monitors.first;
        region = MonitorRect(
            x: fb.left, y: fb.top, w: fb.width, h: fb.height);
        scopeText = '주 화면만 (선택 불일치)';
      } else if (settings.selectedMonitors.isEmpty) {
        scopeText = monitors.length == 1
            ? '화면 1개'
            : '전체 화면 (${monitors.length}개)';
      } else {
        final n = monitors
            .where((m) =>
                settings.selectedMonitors.contains(m.device))
            .length;
        scopeText = '선택 화면 $n/${monitors.length}개';
      }

      String? shotPath;
      try {
        shotPath = await captureRegionPng(
          target,
          x: region.x,
          y: region.y,
          w: region.w,
          h: region.h,
        );
        if (shotPath == null || !await File(shotPath).exists()) {
          shotPath = null;
        }
      } catch (e) {
        lastError = 'capture: $e';
        _mark('캡처 실패');
        return;
      }
      if (shotPath == null) {
        lastError = 'capture: no image produced';
        _mark('캡처 실패');
        return;
      }

      final rawBytes = await File(shotPath).readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        lastError = 'decode failed, kept file';
        _mark('디코딩 실패');
        return;
      }
      // Dual-monitor shots are huge: downscale to max 1600px wide so the
      // timeline stays fast and small. Still plenty for captions later.
      var finalBytes = rawBytes;
      if (decoded.width > 1600) {
        final small = img.copyResize(decoded, width: 1600);
        finalBytes = img.encodePng(small);
        await File(shotPath).writeAsBytes(finalBytes);
      }
      final hash = averageHash(finalBytes);
      if (hash.isEmpty) {
        lastError = 'hash failed, kept file';
        _mark('해시 실패');
        return;
      }

      final prev = _lastHash;
      if (prev != null && hamming(prev, hash) <= dupThreshold) {
        skipped++;
        try {
          await File(shotPath).delete();
        } catch (_) {}
        _mark('중복 스킵');
        return;
      }
      _lastHash = hash;

      final title = activeWindowTitle();
      final id = await TimelineDatabase.instance.insertEntry(
        ts: ts,
        app: 'screen',
        title: title,
        imagePath: shotPath,
        hash: hash,
      );
      saved++;
      lastError = '';
      _mark('저장됨');
      // Caption without blocking the next tick (single-flight).
      _captionSoon(id, shotPath);
    } catch (e) {
      lastError = '$e';
      _mark('오류');
    }
  }

  void _captionSoon(int id, String imagePath) {
    if (captionBusy) return;
    final s = _settings;
    if (s != null && s.provider == Providers.ollama && !ollamaOk) return;
    captionBusy = true;
    notifyListeners();
    _captionWork(id, imagePath);
  }

  Future<void> _captionWork(int id, String imagePath) async {
    try {
      final s = _settings ?? await AppSettings.load();
      _settings = s;
      final bytes = await File(imagePath).readAsBytes();
      final text = await llm.caption(s, bytes);
      final clean = text.isEmpty ? '(캡션 실패)' : text;
      await TimelineDatabase.instance.updateCaption(id, clean);
      captioned++;
    } catch (e) {
      lastError = 'caption: $e';
    } finally {
      captionBusy = false;
      notifyListeners();
    }
  }

  /// Backfill captions for entries saved while the LLM was busy/offline.
  Future<void> fillMissingCaptions() async {
    if (captionBusy) return;
    var s = _settings ?? await AppSettings.load();
    _settings = s;
    if (s.provider == Providers.ollama) {
      ollamaOk = await llm.ollama.alive();
      if (!ollamaOk) {
        lastError = 'Ollama 미연결(127.0.0.1:11434)';
        notifyListeners();
        return;
      }
    }
    captionBusy = true;
    notifyListeners();
    try {
      final rows = await TimelineDatabase.instance.uncapped(limit: 20);
      for (final r in rows) {
        final id = r['id'] as int?;
        final path = r['image_path'] as String?;
        if (id == null || path == null) continue;
        try {
          final bytes = await File(path).readAsBytes();
          final text = await llm.caption(s, bytes);
          await TimelineDatabase.instance
              .updateCaption(id, text.isEmpty ? '(캡션 실패)' : text);
          captioned++;
        } catch (e) {
          lastError = 'caption: $e';
          break;
        }
        notifyListeners();
      }
    } finally {
      captionBusy = false;
      notifyListeners();
    }
  }

  void _mark(String result) {
    lastTick = DateTime.now();
    lastResult = '$result ${_fmtTime(lastTick!)}';
    notifyListeners();
  }

  static String _fmtTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    llm.close();
    super.dispose();
  }
}

/// Foreground window title via Win32. Never throws.
String activeWindowTitle() {
  try {
    final hwnd = GetForegroundWindow();
    if (hwnd == 0) return 'unknown';
    final len = GetWindowTextLength(hwnd);
    if (len == 0) return 'unknown';
    final buf = wsalloc(len + 1);
    try {
      GetWindowText(hwnd, buf, len + 1);
      return buf.toDartString();
    } finally {
      free(buf);
    }
  } catch (_) {
    return 'unknown';
  }
}
