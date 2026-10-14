import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vtt_app/db.dart';

Future<Database> _memDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, version) => TimelineDatabase.createSchema(db),
    ),
  );
}

void main() {
  test('deleteEntries removes rows and files', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_del_');
    try {
      final db = await _memDb();
      final f1 =
          File('${dir.path}${Platform.pathSeparator}a.png');
      final f2 =
          File('${dir.path}${Platform.pathSeparator}b.png');
      await f1.writeAsBytes([1, 2, 3]);
      await f2.writeAsBytes([4, 5, 6, 7]);
      Future<int> row(String path) => db.insert('entries', {
            'ts': 1,
            'app': 'screen',
            'title': 't',
            'image_path': path,
            'hash': 'h',
          });
      final id1 = await row(f1.path);
      final id2 = await row(f2.path);
      final id3 = await row(''); // no file attached

      final res =
          await TimelineDatabase.deleteEntriesOn(db, [id1, id3]);
      expect(res.rows, 2);
      expect(res.files, 1);
      expect(res.bytes, 3);
      expect(await f1.exists(), isFalse);
      expect(await f2.exists(), isTrue);
      final left = await db.query('entries');
      expect(left.length, 1);
      expect(left.first['id'], id2);
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('deleteEntries tolerates missing files', () async {
    final db = await _memDb();
    try {
      final id = await db.insert('entries', {
        'ts': 1,
        'app': 'screen',
        'title': 't',
        'image_path': 'C:/no/such/file.png',
        'hash': 'h',
      });
      final res =
          await TimelineDatabase.deleteEntriesOn(db, [id]);
      expect(res.rows, 1);
      expect(res.files, 0);
      expect(await db.query('entries'), isEmpty);
      await db.close();
    } finally {
      // db closed above
    }
  });
}
