import 'package:flutter/material.dart';

import 'db.dart';
import 'digest_page.dart';

/// Saved diary history.
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await TimelineDatabase.instance.diaries();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(String day, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiaryDetailPage(day: day, content: content)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('일기 기록'),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_agenda_outlined),
            tooltip: '몰아보기',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const DigestPage()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('아직 저장된 일기가 없습니다.'))
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final day = _rows[i]['day'] as String? ?? '';
                    final content = _rows[i]['content'] as String? ?? '';
                    final preview = content.split('\n').take(2).join('\n');
                    return ListTile(
                      leading: const Icon(Icons.book_outlined),
                      title: Text(day),
                      subtitle: Text(preview,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _open(day, content),
                    );
                  },
                ),
    );
  }
}

class DiaryDetailPage extends StatelessWidget {
  final String day;
  final String content;
  const DiaryDetailPage(
      {super.key, required this.day, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(day)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(content),
      ),
    );
  }
}
