import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'db.dart';
import 'diary_page.dart';

/// LIKE search across capture titles/captions and saved diaries.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _deb;
  List<Map<String, Object?>> _entries = [];
  List<Map<String, Object?>> _diaries = [];
  bool _searched = false;

  @override
  void dispose() {
    _deb?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _deb?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _entries = [];
        _diaries = [];
        _searched = false;
      });
      return;
    }
    _deb = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < 2) return;
    try {
      final results = await Future.wait([
        TimelineDatabase.instance.searchEntries(q),
        TimelineDatabase.instance.searchDiaries(q),
      ]);
      if (mounted) {
        setState(() {
          _entries = results[0];
          _diaries = results[1];
          _searched = true;
        });
      }
    } catch (_) {}
  }

  String _fmt(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day} ${two(dt.hour)}:${two(dt.minute)}';
  }

  void _previewEntry(Map<String, Object?> r) {
    final path = r['image_path'] as String? ?? '';
    final title = r['title'] as String? ?? '';
    final caption = r['caption'] as String?;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.isEmpty ? '(제목 없음)' : title,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold)),
              if (caption != null) Text(caption),
              const SizedBox(height: 8),
              Flexible(
                child: File(path).existsSync()
                    ? Image.file(File(path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image))
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
      appBar: AppBar(title: const Text('검색')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '제목·캡션·일기 검색 (2자 이상)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                setState(() {});
                _onChanged(v);
              },
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(
            child: !_searched
                ? const Center(
                    child: Text('2자 이상 입력하면 자동 검색됩니다.'))
                : (_entries.isEmpty && _diaries.isEmpty)
                    ? const Center(child: Text('결과 없음'))
                    : ListView(
                        children: [
                          if (_entries.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 4, 16, 4),
                              child: Text('캡처 ${_entries.length}건',
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.bold)),
                            ),
                          for (final r in _entries)
                            ListTile(
                              leading: const Icon(
                                  Icons.image_outlined),
                              title: Text(
                                (r['title'] as String?)
                                        ?.isNotEmpty ==
                                        true
                                    ? r['title'] as String
                                    : '(제목 없음)',
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_fmt((r['ts'] as int?) ?? 0)} · '
                                '${(r['caption'] as String?) ?? '캡션 없음'}',
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                              onTap: () => _previewEntry(r),
                            ),
                          if (_diaries.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 4),
                              child: Text('일기 ${_diaries.length}건',
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.bold)),
                            ),
                          for (final d in _diaries)
                            ListTile(
                              leading: const Icon(
                                  Icons.book_outlined),
                              title: Text(
                                  d['day'] as String? ?? ''),
                              subtitle: Text(
                                (d['content'] as String?)
                                        ?.split('\n')
                                        .first ??
                                    '',
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DiaryDetailPage(
                                    day: d['day'] as String? ??
                                        '',
                                    content:
                                        d['content'] as String? ??
                                            '',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
