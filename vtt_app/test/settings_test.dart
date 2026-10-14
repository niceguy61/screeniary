import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_app/settings.dart';

void main() {
  test('defaults are sane', () {
    final s = AppSettings();
    expect(s.provider, Providers.ollama);
    expect(
        s.providers[Providers.ollama]!.captionModel, 'qwen2.5vl:3b');
    expect(s.providers[Providers.ollama]!.diaryModel, 'qwen3:8b');
    expect(s.captureIntervalSec, 10);
    expect(s.diaryAuto, isFalse);
  });

  test('save/load roundtrip preserves edits and defaults', () async {
    final dir = await Directory.systemTemp.createTemp('vtt_settings_');
    try {
      final s = AppSettings();
      s.provider = Providers.openai;
      s.providers[Providers.openai]!.apiKey = 'sk-test';
      s.diaryAuto = true;
      s.diaryHour = 22;
      s.diaryMinute = 30;
      s.captureIntervalSec = 15;
      s.lastAutoDiaryDay = '2026-10-14';
      await s.save(dir: dir);

      final loaded = await AppSettings.load(dir: dir);
      expect(loaded.provider, Providers.openai);
      expect(
          loaded.providers[Providers.openai]!.apiKey, 'sk-test');
      expect(loaded.diaryAuto, isTrue);
      expect(loaded.diaryHour, 22);
      expect(loaded.diaryMinute, 30);
      expect(loaded.captureIntervalSec, 15);
      expect(loaded.lastAutoDiaryDay, '2026-10-14');
      expect(loaded.providers[Providers.ollama]!.diaryModel, 'qwen3:8b');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('corrupt file falls back to defaults', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_settings_bad_');
    try {
      await File('${dir.path}${Platform.pathSeparator}settings.json')
          .writeAsString('not json{{{');
      final loaded = await AppSettings.load(dir: dir);
      expect(loaded.provider, Providers.ollama);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
