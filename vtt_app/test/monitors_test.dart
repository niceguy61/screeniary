import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vtt_app/monitors.dart';
import 'package:vtt_app/screen_gdi.dart';
import 'package:vtt_app/settings.dart';

const _fake = [
  MonitorInfo(
      device: 'A', left: 0, top: 0, width: 1920, height: 1080, primary: true),
  MonitorInfo(
      device: 'B',
      left: 1920,
      top: 0,
      width: 1920,
      height: 1080,
      primary: false),
  MonitorInfo(
      device: 'C',
      left: -1280,
      top: 100,
      width: 1280,
      height: 1024,
      primary: false),
];

void main() {
  test('resolveRegion: empty selection covers everything', () {
    final r = resolveRegion(_fake, []);
    expect(r, isNotNull);
    expect(r!.x, -1280);
    expect(r.y, 0);
    expect(r.w, 5120);
    // bottom edge = max(1080, 1080, 1124) = 1124
    expect(r.h, 1124);
  });

  test('resolveRegion: subset unions only chosen monitors', () {
    final r = resolveRegion(_fake, ['B']);
    expect(r, isNotNull);
    expect(r!.x, 1920);
    expect(r.w, 1920);
    expect(r.h, 1080);
  });

  test('resolveRegion: unknown selection returns null', () {
    expect(resolveRegion(_fake, ['ZZZ']), isNull);
    expect(resolveRegion([], ['A']), isNull);
  });

  test('listMonitors finds real screens, exactly one primary', () async {
    final monitors = await listMonitors();
    expect(monitors.isNotEmpty, isTrue);
    expect(monitors.where((m) => m.primary).length, 1);
    final devices = <String>{};
    for (final m in monitors) {
      expect(m.device.isNotEmpty, isTrue);
      expect(m.width > 0 && m.height > 0, isTrue);
      expect(devices.add(m.device), isTrue);
    }
  });

  test('captureRegionPng captures a monitor rect at native size',
      () async {
    final monitors = await listMonitors();
    expect(monitors.isNotEmpty, isTrue);
    final m = monitors.firstWhere((e) => e.primary,
        orElse: () => monitors.first);
    final dir =
        await Directory.systemTemp.createTemp('vtt_region_');
    try {
      final out =
          '${dir.path}${Platform.pathSeparator}region.png';
      final result = await captureRegionPng(out,
          x: m.left, y: m.top, w: m.width, h: m.height);
      expect(result, isNotNull);
      final bytes = await File(out).readAsBytes();
      final image = img.decodeImage(bytes);
      expect(image, isNotNull);
      expect(image!.width, m.width);
      expect(image.height, m.height);
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('selectedMonitors persist', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_set8_');
    try {
      final s = AppSettings();
      s.selectedMonitors = ['\\\\.\\DISPLAY2'];
      await s.save(dir: dir);
      final loaded = await AppSettings.load(dir: dir);
      expect(loaded.selectedMonitors, ['\\\\.\\DISPLAY2']);
      expect(AppSettings().selectedMonitors, isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
