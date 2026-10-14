import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vtt_app/db.dart';
import 'package:vtt_app/timelapse.dart';

Future<void> _png(String path, int r, int g, int b) async {
  final image = img.Image(width: 96, height: 64);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  await File(path).writeAsBytes(img.encodePng(image));
}

void main() {
  test('samplePaths keeps order and endpoints', () {
    final paths = [for (var i = 0; i < 10; i++) 'f$i.png'];
    expect(samplePaths(paths, 20), paths);
    final sampled = samplePaths(paths, 4);
    expect(sampled.length, 4);
    expect(sampled.first, 'f0.png');
    expect(sampled.last, 'f7.png');
    // strictly increasing = order preserved
    final idx = [
      for (final s in sampled) int.parse(s.substring(1, s.length - 4)),
    ];
    for (var i = 1; i < idx.length; i++) {
      expect(idx[i] > idx[i - 1], isTrue);
    }
  });

  test('buildTimelapse writes a valid animated gif', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_gif_');
    try {
      final paths = <String>[];
      final colors = [
        [200, 30, 30],
        [30, 200, 30],
        [30, 30, 200],
        [200, 200, 30],
        [200, 30, 200],
      ];
      for (var i = 0; i < colors.length; i++) {
        final p = '${dir.path}${Platform.pathSeparator}f$i.png';
        await _png(p, colors[i][0], colors[i][1], colors[i][2]);
        paths.add(p);
      }
      // one missing file must be tolerated
      paths.add(
          '${dir.path}${Platform.pathSeparator}gone.png');
      final out =
          '${dir.path}${Platform.pathSeparator}day.gif';
      final res = await buildTimelapse({
        'paths': paths,
        'outPath': out,
        'width': 48,
        'maxFrames': 200,
        'frameMs': 400,
      });
      expect(res['ok'], isTrue);
      expect(res['frames'], 5);
      final bytes = await File(out).readAsBytes();
      expect(
        String.fromCharCodes(bytes.sublist(0, 6)),
        anyOf('GIF89a', 'GIF87a'),
      );
      final decoded = img.decodeGif(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 5);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('buildTimelapse refuses single frame', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_gif1_');
    try {
      final p = '${dir.path}${Platform.pathSeparator}f.png';
      await _png(p, 1, 2, 3);
      final res = await buildTimelapse({
        'paths': [p],
        'outPath': '${dir.path}${Platform.pathSeparator}o.gif',
        'width': 48,
        'maxFrames': 200,
        'frameMs': 400,
      });
      expect(res['ok'], isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('day queries group shots by local day', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) =>
            TimelineDatabase.createSchema(db),
      ),
    );
    try {
      // Two days in local time, noon to dodge DST edges.
      final day1 = DateTime(2026, 10, 10, 12, 0);
      final day2 = DateTime(2026, 10, 12, 12, 0);
      String key(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      Future<void> row(DateTime ts, String path) =>
          db.insert('entries', {
            'ts': ts.millisecondsSinceEpoch,
            'app': 'screen',
            'title': 't',
            'image_path': path,
            'hash': 'h',
          });
      await row(day1.add(const Duration(hours: 2)), 'b.png');
      await row(day1, 'a.png');
      await row(day2, 'c.png');

      final days = await TimelineDatabase.daysWithShotsOn(db);
      expect(days, [key(day2), key(day1)]);
      final shots =
          await TimelineDatabase.shotsForDayOn(db, key(day1));
      expect(shots, ['a.png', 'b.png']);
    } finally {
      await db.close();
    }
  });

  test('huge width keeps native resolution', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_gifn_');
    try {
      final paths = <String>[];
      for (var i = 0; i < 3; i++) {
        final p = '${dir.path}${Platform.pathSeparator}n$i.png';
        await _png(p, 10 * i, 100, 200);
        paths.add(p);
      }
      final out =
          '${dir.path}${Platform.pathSeparator}n.gif';
      final res = await buildTimelapse({
        'paths': paths,
        'outPath': out,
        'width': 100000,
        'maxFrames': 200,
        'frameMs': 400,
      });
      expect(res['ok'], isTrue);
      final decoded =
          img.decodeGif(await File(out).readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, 96);
      expect(decoded.height, 64);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
