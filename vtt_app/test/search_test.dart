import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vtt_app/db.dart';
import 'package:vtt_app/settings.dart';

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

Future<void> _entry(
  Database db,
  int ts,
  String title,
  String? caption,
) =>
    db.insert('entries', {
      'ts': ts,
      'app': 'screen',
      'title': title,
      'image_path': '',
      'hash': 'h',
      'caption': caption,
    });

void main() {
  test('searchEntries matches title and caption, newest first',
      () async {
    final db = await _memDb();
    try {
      await _entry(db, 100, '크롬에서 문서 읽기', null);
      await _entry(db, 200, 'VS Code', '플러터 빌드 중');
      await _entry(db, 300, '메모장', '점심 메뉴 고르기');
      await _entry(db, 400, 'Chrome 메모', null);
      var rows =
          await TimelineDatabase.searchEntriesOn(db, '문서');
      expect(rows.length, 1);
      rows = await TimelineDatabase.searchEntriesOn(db, '고르기');
      expect(rows.length, 1);
      expect(rows.first['title'], '메모장');
      // newest first
      rows = await TimelineDatabase.searchEntriesOn(db, 'e');
      expect(rows.length, 2);
      expect(rows.first['title'], 'Chrome 메모');
      // no hit
      rows = await TimelineDatabase.searchEntriesOn(db, '없는말');
      expect(rows, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('search escapes LIKE wildcards', () async {
    final db = await _memDb();
    try {
      await _entry(db, 1, '100% 완료', null);
      await _entry(db, 2, '그냥 완료', null);
      await _entry(db, 3, '밑줄_테스트', null);
      var rows =
          await TimelineDatabase.searchEntriesOn(db, '100%');
      expect(rows.length, 1);
      expect(rows.first['title'], '100% 완료');
      rows = await TimelineDatabase.searchEntriesOn(db, '_');
      expect(rows.length, 1);
      expect(rows.first['title'], '밑줄_테스트');
    } finally {
      await db.close();
    }
  });

  test('searchDiaries matches content newest first', () async {
    final db = await _memDb();
    try {
      await db.insert('diary', {
        'day': '2026-10-01',
        'content': '오늘은 캡처 기능을 만들었다',
        'created_at': 1,
      });
      await db.insert('diary', {
        'day': '2026-10-03',
        'content': '오늘은 캡처와 일기를 고쳤다',
        'created_at': 3,
      });
      final rows =
          await TimelineDatabase.searchDiariesOn(db, '캡처');
      expect(rows.length, 2);
      expect(rows.first['day'], '2026-10-03');
      final none =
          await TimelineDatabase.searchDiariesOn(db, '없는말');
      expect(none, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('onboarded flag persists', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_onb_');
    try {
      final s = AppSettings();
      expect(s.onboarded, isFalse);
      s.onboarded = true;
      await s.save(dir: dir);
      final loaded = await AppSettings.load(dir: dir);
      expect(loaded.onboarded, isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
