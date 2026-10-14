import 'package:flutter/material.dart';

import 'db.dart';

/// All saved diaries in one scrollable view ("몰아보기").
class DigestPage extends StatefulWidget {
  const DigestPage({super.key});

  @override
  State<DigestPage> createState() => _DigestPageState();
}

class _DigestPageState extends State<DigestPage> {
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await TimelineDatabase.instance.diaries(limit: 200);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('일기 몰아보기')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('아직 저장된 일기가 없습니다.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: _rows.length,
                  itemBuilder: (context, i) {
                    final day = _rows[i]['day'] as String? ?? '';
                    final content =
                        _rows[i]['content'] as String? ?? '';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              day,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(content),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
