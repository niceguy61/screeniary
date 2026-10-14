import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vtt_app/db.dart';
import 'package:vtt_app/retention.dart';
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

Future<File> _shot(
    Directory dir, String name, int ageDays, DateTime now) async {
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(List<int>.filled(1000, 7));
  await f.setLastModified(now.subtract(Duration(days: ageDays)));
  return f;
}

Future<void> _entry(
    Database db, int ts, String path, String hash) async {
  await db.insert('entries', {
    'ts': ts,
    'app': 'screen',
    'title': 't',
    'image_path': path,
    'hash': hash,
  });
}

void main() {
  test('prune deletes old entry files + old orphans, keeps rows', () async {
    final now = DateTime.now();
    final dir = await Directory.systemTemp.createTemp('vtt_ret_');
    try {
      final db = await _memDb();
      final oldTs = now
          .subtract(const Duration(days: 40))
          .millisecondsSinceEpoch;
      final oldFile = await _shot(dir, 'old.png', 40, now);
      final newFile = await _shot(dir, 'new.png', 1, now);
      await _entry(db, oldTs, oldFile.path, 'a');
      await _entry(db, now.millisecondsSinceEpoch, newFile.path, 'b');
      final orphanOld = await _shot(dir, 'orphan_old.png', 50, now);
      final orphanNew = await _shot(dir, 'orphan_new.png', 1, now);

      final res =
          await pruneShots(db, dir, retentionDays: 30, now: now);
      expect(res.deletedFiles, 2);
      expect(res.freedBytes, greaterThan(0));
      expect(await oldFile.exists(), isFalse);
      expect(await newFile.exists(), isTrue);
      expect(await orphanOld.exists(), isFalse);
      expect(await orphanNew.exists(), isTrue);

      final rows = await db.query('entries');
      expect(rows.length, 2); // metadata rows are kept
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('retention 0 keeps everything', () async {
    final now = DateTime.now();
    final dir = await Directory.systemTemp.createTemp('vtt_ret0_');
    try {
      final db = await _memDb();
      final oldFile = await _shot(dir, 'old.png', 100, now);
      await _entry(
        db,
        now
            .subtract(const Duration(days: 100))
            .millisecondsSinceEpoch,
        oldFile.path,
        'a',
      );
      final res =
          await pruneShots(db, dir, retentionDays: 0, now: now);
      expect(res.deletedFiles, 0);
      expect(await oldFile.exists(), isTrue);
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('shotsSize sums files', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_size_');
    try {
      expect(await shotsSize(dir), 0);
      await _shot(dir, 'a.png', 0, DateTime.now());
      await _shot(dir, 'b.png', 0, DateTime.now());
      expect(await shotsSize(dir), 2000);
      expect(formatBytes(2000), '2.0KB');
      expect(formatBytes(500), '500B');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('theme + retention settings persist', () async {
    final dir =
        await Directory.systemTemp.createTemp('vtt_set6_');
    try {
      final s = AppSettings();
      s.themeMode = 'dark';
      s.shotRetentionDays = 15;
      await s.save(dir: dir);
      final loaded = await AppSettings.load(dir: dir);
      expect(loaded.themeMode, 'dark');
      expect(loaded.shotRetentionDays, 15);
      expect(AppSettings.parseTheme('dark'), ThemeMode.dark);
      expect(AppSettings.parseTheme('light'), ThemeMode.light);
      expect(AppSettings.parseTheme('nope'), ThemeMode.system);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('diaries come back newest-first for digest view', () async {
    final db = await _memDb();
    try {
      await db.insert('diary', {
        'day': '2026-10-01',
        'content': 'first',
        'created_at': 1,
      });
      await db.insert('diary', {
        'day': '2026-10-03',
        'content': 'third',
        'created_at': 3,
      });
      final rows =
          await db.query('diary', orderBy: 'day DESC', limit: 200);
      expect(rows.length, 2);
      expect(rows.first['day'], '2026-10-03');
    } finally {
      await db.close();
    }
  });
}
