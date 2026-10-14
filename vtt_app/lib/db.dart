import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DeleteResult {
  final int rows;
  final int files;
  final int bytes;
  const DeleteResult(this.rows, this.files, this.bytes);
}

/// Local timeline store. All data stays on device.
class TimelineDatabase {
  TimelineDatabase._();
  static final TimelineDatabase instance = TimelineDatabase._();

  Database? _db;
  String? dbPath;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS entries(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  app TEXT NOT NULL,
  title TEXT NOT NULL,
  image_path TEXT NOT NULL,
  hash TEXT NOT NULL,
  caption TEXT
)''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_ts ON entries(ts)',
    );
    await createDiaryTable(db);
  }

  static Future<void> createDiaryTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS diary(
  day TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL
)''');
  }

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    dbPath = p.join(dir.path, 'timeline.db');
    final opened = await databaseFactoryFfi.openDatabase(
      dbPath!,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) => createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await createDiaryTable(db);
          }
        },
      ),
    );
    _db = opened;
    return opened;
  }

  Future<int> insertEntry({
    required int ts,
    required String app,
    required String title,
    required String imagePath,
    required String hash,
  }) async {
    final db = await database;
    return db.insert('entries', {
      'ts': ts,
      'app': app,
      'title': title,
      'image_path': imagePath,
      'hash': hash,
    });
  }

  Future<List<Map<String, Object?>>> latest({int limit = 100}) async {
    final db = await database;
    return db.query('entries', orderBy: 'ts DESC', limit: limit);
  }

  Future<int> count() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM entries');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> updateCaption(int id, String caption) async {
    final db = await database;
    await db.update(
      'entries',
      {'caption': caption},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Entries without a caption yet (oldest first).
  Future<List<Map<String, Object?>>> uncapped({int limit = 20}) async {
    final db = await database;
    return db.query(
      'entries',
      where: 'caption IS NULL',
      orderBy: 'ts ASC',
      limit: limit,
    );
  }

  /// Today's entries, oldest first, for the diary prompt.
  Future<List<Map<String, Object?>>> todayRows() async {
    final db = await database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch;
    return db.query(
      'entries',
      where: 'ts >= ?',
      whereArgs: [start],
      orderBy: 'ts ASC',
      limit: 500,
    );
  }

  Future<void> saveDiary(String day, String content) async {
    final db = await database;
    await db.insert(
      'diary',
      {
        'day': day,
        'content': content,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getDiary(String day) async {
    final db = await database;
    final rows = await db.query(
      'diary',
      where: 'day = ?',
      whereArgs: [day],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  Future<List<Map<String, Object?>>> diaries({int limit = 60}) async {
    final db = await database;
    return db.query('diary', orderBy: 'day DESC', limit: limit);
  }

  /// Manual delete: removes rows AND their image files.
  /// (Unlike retention pruning, which keeps metadata rows.)
  Future<DeleteResult> deleteEntries(List<int> ids) async {
    final db = await database;
    return deleteEntriesOn(db, ids);
  }

  static Future<DeleteResult> deleteEntriesOn(
    DatabaseExecutor db,
    List<int> ids,
  ) async {
    var files = 0;
    var bytes = 0;
    for (final id in ids) {
      final rows = await db.query(
        'entries',
        columns: ['image_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final path =
          rows.isEmpty ? null : rows.first['image_path'] as String?;
      if (path != null && path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) {
            bytes += await f.length();
            await f.delete();
            files++;
          }
        } catch (_) {}
      }
      await db.delete('entries', where: 'id = ?', whereArgs: [id]);
    }
    return DeleteResult(ids.length, files, bytes);
  }

  /// Days (local YYYY-MM-DD) that have captures, newest first.
  Future<List<String>> daysWithShots({int limit = 60}) async {
    final db = await database;
    return daysWithShotsOn(db, limit: limit);
  }

  static Future<List<String>> daysWithShotsOn(
    DatabaseExecutor db, {
    int limit = 60,
  }) async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT date(ts/1000, \'unixepoch\', \'localtime\') AS d '
      'FROM entries ORDER BY d DESC LIMIT ?',
      [limit],
    );
    return [for (final r in rows) r['d'] as String];
  }

  /// Screenshot paths for one local day, oldest first.
  Future<List<String>> shotsForDay(String day, {int limit = 2000}) async {
    final db = await database;
    return shotsForDayOn(db, day, limit: limit);
  }

  static Future<List<String>> shotsForDayOn(
    DatabaseExecutor db,
    String day, {
    int limit = 2000,
  }) async {
    final rows = await db.query(
      'entries',
      columns: ['image_path'],
      where: 'date(ts/1000, \'unixepoch\', \'localtime\') = ?',
      whereArgs: [day],
      orderBy: 'ts ASC',
      limit: limit,
    );
    return [
      for (final r in rows)
        if ((r['image_path'] as String?)?.isNotEmpty ?? false)
          r['image_path'] as String,
    ];
  }
}
