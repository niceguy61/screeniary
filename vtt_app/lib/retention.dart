import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PruneResult {
  final int deletedFiles;
  final int freedBytes;
  const PruneResult(this.deletedFiles, this.freedBytes);
  const PruneResult.none() : this(0, 0);
}

/// Deletes screenshot image files older than [retentionDays].
///
/// Diary rows are never touched, and timeline metadata rows are kept —
/// only the heavy PNG files go away (thumbnails then show a placeholder).
/// Also sweeps orphaned files in [shotsDir] with no DB reference.
/// [retentionDays] <= 0 means "keep forever".
Future<PruneResult> pruneShots(
  DatabaseExecutor db,
  Directory shotsDir, {
  required int retentionDays,
  DateTime? now,
}) async {
  if (retentionDays <= 0) return const PruneResult.none();
  final t = now ?? DateTime.now();
  final cutoff =
      t.subtract(Duration(days: retentionDays)).millisecondsSinceEpoch;

  final referenced = <String>{};
  var files = 0;
  var bytes = 0;

  Future<void> deleteIfOld(String path) async {
    final f = File(path);
    if (!await f.exists()) return;
    try {
      bytes += await f.length();
      await f.delete();
      files++;
    } catch (_) {}
  }

  final oldRows = await db.query(
    'entries',
    columns: ['image_path'],
    where: 'ts < ?',
    whereArgs: [cutoff],
  );
  for (final r in oldRows) {
    final path = r['image_path'] as String?;
    if (path == null || path.isEmpty) continue;
    referenced.add(path);
    await deleteIfOld(path);
  }

  if (await shotsDir.exists()) {
    await for (final e in shotsDir.list()) {
      if (e is! File) continue;
      if (referenced.contains(e.path)) continue;
      try {
        final stat = await e.stat();
        if (stat.modified.millisecondsSinceEpoch < cutoff) {
          bytes += stat.size;
          await e.delete();
          files++;
        }
      } catch (_) {}
    }
  }

  return PruneResult(files, bytes);
}

/// Total size of stored screenshots, for the storage section in settings.
Future<int> shotsSize(Directory shotsDir) async {
  var total = 0;
  try {
    if (!await shotsDir.exists()) return 0;
    await for (final e in shotsDir.list(recursive: true)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
}
