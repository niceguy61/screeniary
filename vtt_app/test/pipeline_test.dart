import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:vtt_app/db.dart';
import 'package:vtt_app/hash.dart';
import 'package:vtt_app/screen_gdi.dart';

img.Image _solid(int r, int g, int b) {
  final image = img.Image(width: 64, height: 64);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return image;
}

void main() {
  test('ahash: identical images distance 0, inverted images far apart', () {
    final a = _solid(10, 10, 10);
    final bytes = Uint8List.fromList(img.encodePng(a));
    final h1 = averageHash(bytes);
    final h2 = averageHash(bytes);
    expect(h1.length, 64);
    expect(hamming(h1, h2), 0);

    final half = img.Image(width: 64, height: 64);
    img.fill(half, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      half,
      x1: 0,
      y1: 0,
      x2: 31,
      y2: 63,
      color: img.ColorRgb8(0, 0, 0),
    );
    final h3 = averageHash(Uint8List.fromList(img.encodePng(half)));
    expect(h3.length, 64);
    expect(hamming(h1, h3) > 5, isTrue);
  });

  test('db: insert + query roundtrip on shared schema', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => TimelineDatabase.createSchema(db),
      ),
    );
    final id = await db.insert('entries', {
      'ts': 123,
      'app': 'screen',
      'title': 'test window',
      'image_path': 'C:/tmp/1.png',
      'hash': '0' * 64,
    });
    expect(id, 1);
    final rows = await db.query('entries');
    expect(rows.length, 1);
    expect(rows.first['title'], 'test window');
    await db.close();
  });

  test('gdi: real screen capture produces decodable png', () async {
    final dir = await Directory.systemTemp.createTemp('vtt_gdi_');
    try {
      final out = '${dir.path}${Platform.pathSeparator}shot.png';
      final result = await captureScreenPng(out);
      expect(result, isNotNull);
      final bytes = await File(out).readAsBytes();
      expect(bytes.lengthInBytes > 10000, isTrue);
      expect(img.decodeImage(bytes), isNotNull);
      expect(averageHash(bytes).length, 64);
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
