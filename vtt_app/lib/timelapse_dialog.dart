import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'retention.dart';
import 'timelapse.dart';

/// Per-day timelapse GIF export dialog.
class TimelapseDialog extends StatefulWidget {
  const TimelapseDialog({super.key});

  @override
  State<TimelapseDialog> createState() => _TimelapseDialogState();
}

class _TimelapseDialogState extends State<TimelapseDialog> {
  List<String> _days = [];
  String? _day;
  int _shots = 0;
  int _speedMs = 400;
  // 0 = native resolution, else max width.
  int _res = 0;
  bool _loading = true;
  bool _busy = false;
  String _result = '';

  int get _maxFrames => _res == 0 ? 80 : 200;

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  Future<void> _loadDays() async {
    try {
      final days = await TimelineDatabase.instance.daysWithShots();
      String? pick;
      if (days.isNotEmpty) {
        final today = _todayKey();
        pick = days.contains(today) ? today : days.first;
      }
      if (mounted) {
        setState(() {
          _days = days;
          _day = pick;
          _loading = false;
        });
      }
      if (pick != null) await _countShots(pick);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  Future<void> _countShots(String day) async {
    final shots =
        await TimelineDatabase.instance.shotsForDay(day);
    if (mounted) setState(() => _shots = shots.length);
  }

  Future<void> _generate() async {
    final day = _day;
    if (day == null || _busy) return;
    setState(() {
      _busy = true;
      _result = '';
    });
    try {
      final shots =
          await TimelineDatabase.instance.shotsForDay(day);
      if (shots.isEmpty) {
        setState(() => _result = '해당 날짜의 캡처가 없습니다.');
        return;
      }
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
          '${docs.path}${Platform.pathSeparator}VTT');
      if (!await dir.exists()) await dir.create(recursive: true);
      final outPath =
          '${dir.path}${Platform.pathSeparator}timelapse-$day.gif';
      final res = await compute(buildTimelapse, {
        'paths': shots,
        'outPath': outPath,
        'width': _res == 0 ? 100000 : _res,
        'maxFrames': _maxFrames,
        'frameMs': _speedMs,
        // Native 4K frames quantize slowly: sample coarsely, it's a timelapse.
        'sampling': _res == 0 ? 30 : 10,
      });
      if (!mounted) return;
      if (res['ok'] == true) {
        setState(() => _result =
            'ok|${res['frames']}|${res['bytes']}|${res['path']}');
      } else {
        setState(() => _result =
            '프레임 부족 (${res['frames']}장, 최소 2장 필요)');
      }
    } catch (e) {
      if (mounted) setState(() => _result = '실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFolder(String path) async {
    try {
      await Process.run('explorer.exe', ['/select,', path]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ok = _result.startsWith('ok|');
    final parts = ok ? _result.split('|') : const <String>[];
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('하루 타임랩스 GIF',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_days.isEmpty)
              const Text('캡처 기록이 없습니다.')
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey(_day),
                initialValue: _day,
                decoration: const InputDecoration(
                  labelText: '날짜',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final d in _days)
                    DropdownMenuItem(value: d, child: Text(d)),
                ],
                onChanged: _busy
                    ? null
                    : (v) async {
                        if (v == null) return;
                        setState(() {
                          _day = v;
                          _shots = 0;
                          _result = '';
                        });
                        await _countShots(v);
                      },
              ),
              const SizedBox(height: 8),
              Text('$_shots장 → 최대 $_maxFrames프레임으로 균등 샘플링',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey('res-$_res'),
                initialValue: _res,
                decoration: const InputDecoration(
                  labelText: '해상도',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 0, child: Text('원본 (캡처 해상도 그대로)')),
                  DropdownMenuItem(
                      value: 1920, child: Text('FHD (1920px)')),
                  DropdownMenuItem(
                      value: 960, child: Text('960px')),
                  DropdownMenuItem(
                      value: 480, child: Text('480px (가벼움)')),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _res = v ?? 0),
              ),
              const SizedBox(height: 4),
              const Text('원본 4K는 수백MB·수 분 걸릴 수 있음',
                  style: TextStyle(fontSize: 11)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey(_speedMs),
                initialValue: _speedMs,
                decoration: const InputDecoration(
                  labelText: '재생 속도',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 200, child: Text('빠르게 (0.2초/장)')),
                  DropdownMenuItem(
                      value: 400, child: Text('보통 (0.4초/장)')),
                  DropdownMenuItem(
                      value: 800, child: Text('느리게 (0.8초/장)')),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _speedMs = v ?? 400),
              ),
              const SizedBox(height: 12),
              if (_busy)
                const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('GIF 만드는 중... (수십 초 소요)'),
                  ],
                )
              else if (ok)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${parts[1]}프레임 · ${formatBytes(int.parse(parts[2]))}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold),
                    ),
                    Text(parts.sublist(3).join('|'),
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _openFolder(parts.sublist(3).join('|')),
                          child: const Text('폴더 열기'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('닫기'),
                        ),
                      ],
                    ),
                  ],
                )
              else ...[
                if (_result.isNotEmpty) Text(_result),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _generate,
                      child: const Text('GIF 만들기'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
