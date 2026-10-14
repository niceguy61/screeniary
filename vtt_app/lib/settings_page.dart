import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'capture_service.dart';
import 'db.dart';
import 'llm.dart';
import 'monitors.dart';
import 'retention.dart';
import 'settings.dart';

/// LLM provider / capture / auto-diary settings.
class SettingsPage extends StatefulWidget {
  final CaptureService svc;
  final ValueChanged<ThemeMode>? onThemeChanged;
  const SettingsPage({super.key, required this.svc, this.onThemeChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings? _s;
  final _controllers = <String, TextEditingController>{};
  bool _testing = false;
  String _testMsg = '';
  bool _pruning = false;
  String _shotsInfo = '계산 중...';
  List<MonitorInfo> _monitors = [];

  TextEditingController _c(String key) =>
      _controllers.putIfAbsent(key, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AppSettings.load();
    _fillControllers(s);
    if (mounted) setState(() => _s = s);
    await _refreshShotsSize();
    try {
      final monitors = await listMonitors();
      if (mounted) setState(() => _monitors = monitors);
    } catch (_) {}
  }

  void _toggleMonitor(String device, bool on) {
    final s = _s;
    if (s == null) return;
    final all = [for (final m in _monitors) m.device];
    final current =
        s.selectedMonitors.isEmpty ? all : s.selectedMonitors;
    List<String> next;
    if (on) {
      next = {...current, device}.toList();
    } else {
      next = current.where((d) => d != device).toList();
    }
    // Everything checked == default "record all" → store empty.
    if (next.length == all.length && next.toSet().containsAll(all)) {
      next = [];
    }
    setState(() => s.selectedMonitors = next);
  }

  Future<Directory> _shotsDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
        '${support.path}${Platform.pathSeparator}shots');
  }

  Future<void> _refreshShotsSize() async {
    try {
      final size = await shotsSize(await _shotsDir());
      if (mounted) {
        setState(() => _shotsInfo = '캡처 이미지: ${formatBytes(size)}');
      }
    } catch (_) {
      if (mounted) setState(() => _shotsInfo = '크기 확인 실패');
    }
  }

  Future<void> _sendFeedback() async {
    if (feedbackFormUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('피드백 폼 준비 중입니다. 다음 업데이트에서 열립니다.')),
        );
      }
      return;
    }
    try {
      await Process.run('explorer.exe', [feedbackFormUrl]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('브라우저 열기 실패: $e')),
        );
      }
    }
  }

  Future<void> _pruneNow() async {    final s = _s;
    if (s == null || _pruning) return;
    _stashControllers(s);
    setState(() => _pruning = true);
    try {
      final res = await pruneShots(
        await TimelineDatabase.instance.database,
        await _shotsDir(),
        retentionDays: s.shotRetentionDays,
      );
      await _refreshShotsSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.deletedFiles == 0
                  ? '정리할 캡처가 없습니다 (일기·기록은 유지됨)'
                  : '${res.deletedFiles}장 정리, '
                      '${formatBytes(res.freedBytes)} 확보 (일기·기록은 유지)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pruning = false);
    }
  }

  void _fillControllers(AppSettings s) {
    final cfg = s.active;
    _c('apiKey').text = cfg.apiKey;
    _c('baseUrl').text = cfg.baseUrl;
    _c('captionModel').text = cfg.captionModel;
    _c('diaryModel').text = cfg.diaryModel;
    _c('region').text = cfg.region;
    _c('awsAccessKey').text = cfg.awsAccessKey;
    _c('awsSecretKey').text = cfg.awsSecretKey;
  }

  void _stashControllers(AppSettings s) {
    final cfg = s.active;
    cfg.apiKey = _c('apiKey').text.trim();
    cfg.baseUrl = _c('baseUrl').text.trim();
    cfg.captionModel = _c('captionModel').text.trim();
    cfg.diaryModel = _c('diaryModel').text.trim();
    cfg.region = _c('region').text.trim();
    cfg.awsAccessKey = _c('awsAccessKey').text.trim();
    cfg.awsSecretKey = _c('awsSecretKey').text;
  }

  void _switchProvider(String? p) {
    if (p == null || _s == null || p == _s!.provider) return;
    _stashControllers(_s!);
    _s!.provider = p;
    _fillControllers(_s!);
    setState(() {
      _testMsg = '';
    });
  }

  Future<void> _save() async {
    final s = _s;
    if (s == null) return;
    _stashControllers(s);
    await s.save();
    await widget.svc.reloadSettings();
    widget.onThemeChanged?.call(AppSettings.parseTheme(s.themeMode));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정 저장됨 (캡처 간격은 다음 시작부터 적용)')),
      );
    }
  }

  Future<void> _test() async {
    final s = _s;
    if (s == null || _testing) return;
    final probe = AppSettings.fromJson(s.toJson());
    _stashControllers(probe);
    setState(() {
      _testing = true;
      _testMsg = '';
    });
    final client = LlmClient();
    try {
      final r = await client.probe(probe);
      final short = r.length > 120 ? '${r.substring(0, 120)}…' : r;
      setState(() => _testMsg = '성공: $short');
    } catch (e) {
      setState(() => _testMsg = '실패: $e');
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _pickTime() async {
    final s = _s;
    if (s == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.diaryHour, minute: s.diaryMinute),
    );
    if (picked != null) {
      setState(() {
        s.diaryHour = picked.hour;
        s.diaryMinute = picked.minute;
      });
    }
  }

  Widget _field(String key, String label, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c(key),
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  List<Widget> _providerFields(String provider) {
    switch (provider) {
      case Providers.ollama:
        return [
          const Text('로컬 Ollama 사용. 키 불필요.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          _field('captionModel', '캡션 모델 (VLM)'),
          _field('diaryModel', '일기 모델 (LLM)'),
        ];
      case Providers.openai:
      case Providers.openrouter:
        return [
          _field('apiKey', 'API Key', obscure: true),
          _field('baseUrl', 'Base URL'),
          _field('captionModel', '캡션 모델 (vision 지원)'),
          _field('diaryModel', '일기 모델'),
        ];
      case Providers.anthropic:
        return [
          _field('apiKey', 'API Key', obscure: true),
          _field('captionModel', '캡션 모델 (vision 지원)'),
          _field('diaryModel', '일기 모델'),
        ];
      case Providers.bedrock:
        return [
          _field('awsAccessKey', 'AWS Access Key ID'),
          _field('awsSecretKey', 'AWS Secret Access Key', obscure: true),
          _field('region', 'Region (예: us-east-1)'),
          _field('captionModel', '캡션 모델 ID (예: amazon.nova-lite-v1:0)'),
          _field('diaryModel', '일기 모델 ID'),
        ];
      default:
        return [];
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('LLM 제공자',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey(s.provider),
                  initialValue: s.provider,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final e in Providers.labels.entries)
                      DropdownMenuItem(
                          value: e.key, child: Text(e.value)),
                  ],
                  onChanged: _switchProvider,
                ),
                const SizedBox(height: 12),
                ..._providerFields(s.provider),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _testing ? null : _test,
                        child: Text(_testing ? '테스트 중...' : '연결 테스트'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _save,
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                ),
                if (_testMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_testMsg,
                        style: const TextStyle(fontSize: 12)),
                  ),
                const Divider(height: 32),
                const Text('화면',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('theme-${s.themeMode}'),
                  initialValue: s.themeMode,
                  decoration: const InputDecoration(
                    labelText: '테마',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'system', child: Text('시스템 설정 따르기')),
                    DropdownMenuItem(
                        value: 'light', child: Text('라이트')),
                    DropdownMenuItem(
                        value: 'dark', child: Text('다크')),
                  ],
                  onChanged: (v) =>
                      setState(() => s.themeMode = v ?? 'system'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('ret-${s.shotRetentionDays}'),
                  initialValue: s.shotRetentionDays,
                  decoration: const InputDecoration(
                    labelText: '캡처 보관 기간 (일기·기록은 유지)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 0, child: Text('무기한 보관')),
                    DropdownMenuItem(
                        value: 7, child: Text('7일')),
                    DropdownMenuItem(
                        value: 15, child: Text('15일')),
                    DropdownMenuItem(
                        value: 30, child: Text('30일')),
                    DropdownMenuItem(
                        value: 90, child: Text('90일')),
                  ],
                  onChanged: (v) => setState(
                      () => s.shotRetentionDays = v ?? 30),
                ),
                const Divider(height: 32),
                const Text('캡처 화면',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Text(
                    '체크한 화면만 기록. 현재 연결된 화면만 표시되며, '
                    '캡처 중 추가된 화면은 포함되지 않음.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                if (_monitors.isEmpty)
                  const Text('화면 목록을 불러오는 중...',
                      style: TextStyle(fontSize: 12))
                else
                  for (final m in _monitors)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.label,
                          style:
                              const TextStyle(fontSize: 13)),
                      value: s.selectedMonitors.isEmpty ||
                          s.selectedMonitors.contains(m.device),
                      onChanged: (v) =>
                          _toggleMonitor(m.device, v ?? false),
                    ),
                const Divider(height: 32),
                const Text('캡처',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: s.captureIntervalSec.toDouble(),
                        min: 5,
                        max: 60,
                        divisions: 11,
                        label: '${s.captureIntervalSec}초',
                        onChanged: (v) => setState(
                            () => s.captureIntervalSec = v.round()),
                      ),
                    ),
                    Text('${s.captureIntervalSec}초 간격'),
                  ],
                ),
                const Divider(height: 32),
                const Text('자동 일기',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Text('지정 시간이 되면 오늘 일기를 자동 생성 (앱 실행 중에만 동작)',
                    style: TextStyle(fontSize: 12)),
                SwitchListTile(
                  title: const Text('자동 일기 켜기'),
                  value: s.diaryAuto,
                  onChanged: (v) => setState(() => s.diaryAuto = v),
                ),
                Row(
                  children: [
                    const Text('생성 시간  '),
                    OutlinedButton(
                      onPressed: _pickTime,
                      child: Text(
                          '${_two(s.diaryHour)}:${_two(s.diaryMinute)}'),
                    ),
                  ],
                ),
                const Divider(height: 32),
                const Text('저장 공간',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                Text(_shotsInfo,
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _pruning ? null : _pruneNow,
                  child:
                      Text(_pruning ? '정리 중...' : '오래된 캡처 지금 정리'),
                ),
                const Divider(height: 32),
                const Text('피드백',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const Text(
                    '불편한 점·버그·원하는 기능을 보내주세요. '
                    '앱 상단의 버전을 함께 적어주면 원인 파악이 빠릅니다.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _sendFeedback,
                  icon: const Icon(Icons.feedback_outlined, size: 18),
                  label: const Text('피드백 보내기'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
