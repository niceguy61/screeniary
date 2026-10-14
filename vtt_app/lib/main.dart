import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'capture_service.dart';
import 'db.dart';
import 'diary_page.dart';
import 'monitors.dart';
import 'retention.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'timelapse_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _showWindowSafely();
  runApp(const VttApp());
}

/// Shows the window, recentering it when it was stranded on a monitor
/// that no longer exists (e.g. dual → single switch).
/// The margin keeps this safe under DPI scale mismatches: it only moves
/// windows that are far outside every connected screen.
Future<void> _showWindowSafely() async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1100, 750),
        minimumSize: Size(800, 600),
        title: 'VTT',
      ),
      () async {
        try {
          final pos = await windowManager.getPosition();
          final monitors = await listMonitors();
          if (monitors.isNotEmpty) {
            var l = monitors.first.left.toDouble();
            var t = monitors.first.top.toDouble();
            var r = l + monitors.first.width;
            var b = t + monitors.first.height;
            for (final m in monitors.skip(1)) {
              if (m.left < l) l = m.left.toDouble();
              if (m.top < t) t = m.top.toDouble();
              final mr = m.left + m.width.toDouble();
              final mb = m.top + m.height.toDouble();
              if (mr > r) r = mr;
              if (mb > b) b = mb;
            }
            const margin = 400.0;
            if (pos.dx > r + margin ||
                pos.dx < l - margin ||
                pos.dy > b + margin ||
                pos.dy < t - margin) {
              await windowManager.center();
            }
          }
        } catch (_) {}
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (_) {}
}

class VttApp extends StatefulWidget {
  const VttApp({super.key});

  @override
  State<VttApp> createState() => _VttAppState();
}

class _VttAppState extends State<VttApp> {
  ThemeMode _mode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final s = await AppSettings.load();
    if (mounted) {
      setState(() => _mode = AppSettings.parseTheme(s.themeMode));
    }
  }

  void _setTheme(ThemeMode mode) {
    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VTT - Visual Time Travel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _mode,
      home: TimelinePage(onThemeChanged: _setTheme),
    );
  }
}

class _RecDot extends StatelessWidget {
  const _RecDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.red,
      ),
    );
  }
}

class TimelinePage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;
  const TimelinePage({super.key, required this.onThemeChanged});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final _svc = CaptureService();
  List<Map<String, Object?>> _rows = [];
  int _total = 0;
  final _selected = <int>{};
  String _initError = '';
  bool _ready = false;
  bool _diaryBusy = false;
  Timer? _sched;
  DateTime? _lastPrune;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onServiceChanged);
    _init();
    // Auto-diary scheduler (works while the app is running).
    _sched = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkAutoDiary(),
    );
  }

  Future<void> _init() async {
    try {
      await TimelineDatabase.instance.database;
      if (mounted) setState(() => _ready = true);
      await _refresh();
      await _pruneIfDue(force: true);
    } catch (e) {
      if (mounted) setState(() => _initError = '$e');
    }
  }

  /// Deletes old screenshot files (metadata + diaries are kept).
  /// Runs at startup and at most every 6 hours afterwards.
  Future<void> _pruneIfDue({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastPrune != null &&
        now.difference(_lastPrune!) < const Duration(hours: 6)) {
      return;
    }
    _lastPrune = now;
    try {
      final s = await AppSettings.load();
      if (s.shotRetentionDays <= 0) return;
      final support = await getApplicationSupportDirectory();
      final db = await TimelineDatabase.instance.database;
      final res = await pruneShots(
        db,
        Directory(
            '${support.path}${Platform.pathSeparator}shots'),
        retentionDays: s.shotRetentionDays,
        now: now,
      );
      if (res.deletedFiles > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '오래된 캡처 ${res.deletedFiles}장 정리 '
              '(${formatBytes(res.freedBytes)} 확보, 일기·기록은 유지)',
            ),
          ),
        );
        await _refresh();
      }
    } catch (_) {}
  }

  void _onServiceChanged() {
    _refresh();
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      final rows = await TimelineDatabase.instance.latest(limit: 100);
      final total = await TimelineDatabase.instance.count();
      if (mounted) {
        setState(() {
          _rows = rows;
          _total = total;
        });
      }
    } catch (_) {}
  }

  String _todayKey() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  Future<void> _makeDiary() async {
    if (_diaryBusy) return;
    setState(() => _diaryBusy = true);
    try {
      final rows = await TimelineDatabase.instance.todayRows();
      if (rows.isEmpty) {
        _showDiaryDialog('오늘 기록이 아직 없습니다. 캡처를 먼저 쌓아주세요.');
        return;
      }
      final buf = StringBuffer();
      for (final r in rows) {
        final ts = r['ts'] as int? ?? 0;
        final title = r['title'] as String? ?? '';
        final caption = r['caption'] as String?;
        buf.writeln('- ${_fmt(ts)} | $title${caption == null ? '' : ' | $caption'}');
      }
      // Diary runs on the diary model; captions use the caption model. The
      // service single-flights captions, and auto/manual diary runs are
      // serialized through _diaryBusy, so two models never load at once.
      final settings = await AppSettings.load();
      final text = await _svc.llm.diary(settings, buf.toString());
      await TimelineDatabase.instance.saveDiary(_todayKey(), text);
      await _refresh();
      if (mounted) _showDiaryDialog(text);
    } catch (e) {
      if (mounted) _showDiaryDialog('일기 생성 실패: $e');
    } finally {
      if (mounted) setState(() => _diaryBusy = false);
    }
  }

  Future<void> _checkAutoDiary() async {
    await _pruneIfDue();
    if (_diaryBusy || !_ready) return;
    try {
      final s = await AppSettings.load();
      if (!s.diaryAuto) return;
      final today = _todayKey();
      if (s.lastAutoDiaryDay == today) return;
      final now = DateTime.now();
      final due =
          DateTime(now.year, now.month, now.day, s.diaryHour, s.diaryMinute);
      if (now.isBefore(due)) return;
      s.lastAutoDiaryDay = today;
      await s.save();
      await _makeDiary();
    } catch (_) {}
  }

  void _showDiaryDialog(String text) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('오늘의 일기 (${_todayKey()})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(child: Text(text)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sched?.cancel();
    _svc.removeListener(_onServiceChanged);
    _svc.dispose();
    super.dispose();
  }

  String _fmt(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 26,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : scheme.primary,
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _recordButton() {
    final running = _svc.running;
    final scheme = Theme.of(context).colorScheme;
    final enabled = _ready;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: !enabled
              ? null
              : () => running ? _svc.stop() : _svc.start(),
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !enabled
                  ? scheme.surfaceContainerHighest
                  : running
                      ? scheme.errorContainer
                      : Colors.red,
              border: Border.all(
                color: !enabled
                    ? scheme.outlineVariant
                    : running
                        ? scheme.error
                        : Colors.red.shade700,
                width: 3,
              ),
            ),
            child: Icon(
              running
                  ? Icons.stop_rounded
                  : Icons.fiber_manual_record,
              size: 30,
              color: !enabled
                  ? scheme.onSurfaceVariant
                  : running
                      ? scheme.onErrorContainer
                      : Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          running ? '정지' : '녹화',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete(int n) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$n건 삭제할까요?'),
        content:
            const Text('이미지 파일도 함께 삭제됩니다. 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteIds(List<int> ids) async {
    try {
      final res =
          await TimelineDatabase.instance.deleteEntries(ids);
      _selected.removeWhere((id) => ids.contains(id));
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${res.rows}건 삭제 (이미지 ${res.files}장, 일기는 유지)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  void _showPreview(String path, String title, int ts) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? '(제목 없음)' : title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(_fmt(ts), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Flexible(
                child: File(path).existsSync()
                    ? Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image),
                      )
                    : const Icon(Icons.image_not_supported),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VTT 0.5.7 · 오늘 타임라인'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist_outlined),
            tooltip: '선택',
            onPressed: _rows.isEmpty
                ? null
                : () {
                    final id = _rows.first['id'] as int?;
                    if (id != null) {
                      setState(() => _selected.add(id));
                    }
                  },
          ),
          TextButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const TimelapseDialog(),
            ),
            icon: const Icon(Icons.movie_outlined, size: 20),
            label: const Text('타임랩스'),
          ),
          IconButton(
            icon: const Icon(Icons.book_outlined),
            tooltip: '일기 기록',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiaryPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(
                  svc: _svc,
                  onThemeChanged: widget.onThemeChanged,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ready
                          ? '저장 ${_svc.saved} · 중복제거 ${_svc.skipped} · 캡션 ${_svc.captioned} · DB 총 $_total건'
                          : (_initError.isEmpty
                              ? 'DB 초기화 중...'
                              : 'DB 오류: $_initError'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    if (_ready && _svc.running)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: const [
                            _RecDot(),
                            SizedBox(width: 6),
                            Text('녹화 중',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (_ready)
                      Text(
                        '마지막: ${_svc.lastResult} · 범위: ${_svc.scopeText}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (_ready && _svc.lastError.isNotEmpty)
                      Text(
                        '오류: ${_svc.lastError}',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(
                    child: Text(
                      '아직 기록 없음.\n"지금 캡처" 또는 "캡처 시작"을 눌러보세요.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      final id = r['id'] as int?;
                      final path = r['image_path'] as String? ?? '';
                      final title = r['title'] as String? ?? '';
                      final ts = r['ts'] as int? ?? 0;
                      final caption = r['caption'] as String?;
                      final selecting = _selected.isNotEmpty;
                      final tile = ListTile(
                        onTap: id == null
                            ? null
                            : () {
                                if (selecting) {
                                  setState(() {
                                    if (_selected.contains(id)) {
                                      _selected.remove(id);
                                    } else {
                                      _selected.add(id);
                                    }
                                  });
                                } else {
                                  _showPreview(path, title, ts);
                                }
                              },
                        onLongPress: id == null
                            ? null
                            : () =>
                                setState(() => _selected.add(id)),
                        leading: selecting
                            ? Checkbox(
                                value: id != null &&
                                    _selected.contains(id),
                                onChanged: id == null
                                    ? null
                                    : (v) => setState(() {
                                          if (v == true) {
                                            _selected.add(id);
                                          } else {
                                            _selected.remove(id);
                                          }
                                        }),
                              )
                            : SizedBox(
                                width: 96,
                                height: 54,
                                child: File(path).existsSync()
                                    ? Image.file(
                                        File(path),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const Icon(
                                                Icons.broken_image),
                                      )
                                    : const Icon(
                                        Icons.image_not_supported),
                              ),
                        title: Text(
                          title.isEmpty ? '(제목 없음)' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_fmt(ts)} · ${caption ?? '캡션 대기 중'}',
                        ),
                      );
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: id == null || selecting
                            ? tile
                            : Dismissible(
                                key: ValueKey(id),
                                direction:
                                    DismissDirection.endToStart,
                                background: Container(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  alignment:
                                      Alignment.centerRight,
                                  padding: const EdgeInsets.only(
                                      right: 20),
                                  child: const Icon(
                                      Icons.delete_outlined),
                                ),
                                confirmDismiss: (_) =>
                                    _confirmDelete(1),
                                onDismissed: (_) =>
                                    _deleteIds([id]),
                                child: tile,
                              ),
                      );
                    },
                  ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_selected.length}개 선택',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _selected.clear()),
                    child: const Text('해제'),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      if (await _confirmDelete(_selected.length) ==
                          true) {
                        await _deleteIds(_selected.toList());
                      }
                    },
                    child: const Text('삭제'),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _controlButton(
                        icon: Icons.photo_camera_outlined,
                        label: '캡처',
                        onTap: !_ready
                            ? null
                            : () => _svc.captureOnce(),
                      ),
                      _recordButton(),
                      _controlButton(
                        icon: Icons.edit_note_outlined,
                        label: _diaryBusy ? '쓰는 중' : '일기',
                        onTap: !_ready || _diaryBusy
                            ? null
                            : _makeDiary,
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: !_ready || _svc.captionBusy
                        ? null
                        : () => _svc.fillMissingCaptions(),
                    child: Text(_svc.captionBusy
                        ? '캡션 생성 중...'
                        : '빈 캡션 채우기'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
