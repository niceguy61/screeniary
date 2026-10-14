import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Google Form feedback URL. Empty until the form is created.
const feedbackFormUrl =
    'https://docs.google.com/forms/d/e/1FAIpQLSe0UnqdcpDOEHKyaLU-uBZ-XGuYa3avuJEgJJ9CRfR0NSnp-Q/viewform?usp=header';

/// Provider ids. 'openrouter' reuses the OpenAI-compatible wire format.
class Providers {
  static const ollama = 'ollama';
  static const openai = 'openai';
  static const openrouter = 'openrouter';
  static const anthropic = 'anthropic';
  static const bedrock = 'bedrock';
  static const gemini = 'gemini';

  static const labels = {
    ollama: 'Ollama (로컬)',
    openai: 'OpenAI',
    openrouter: 'OpenRouter',
    anthropic: 'Anthropic Claude',
    bedrock: 'AWS Bedrock',
    gemini: 'Google Gemini',
  };
}

class ProviderConfig {
  String apiKey;
  String captionModel;
  String diaryModel;

  /// OpenAI-compatible endpoint base (openai/openrouter).
  String baseUrl;

  /// Bedrock: region + credentials.
  String region;
  String awsAccessKey;
  String awsSecretKey;

  ProviderConfig({
    this.apiKey = '',
    this.captionModel = '',
    this.diaryModel = '',
    this.baseUrl = '',
    this.region = 'us-east-1',
    this.awsAccessKey = '',
    this.awsSecretKey = '',
  });

  factory ProviderConfig.fromJson(Map<String, dynamic> j) => ProviderConfig(
        apiKey: j['apiKey'] as String? ?? '',
        captionModel: j['captionModel'] as String? ?? '',
        diaryModel: j['diaryModel'] as String? ?? '',
        baseUrl: j['baseUrl'] as String? ?? '',
        region: j['region'] as String? ?? 'us-east-1',
        awsAccessKey: j['awsAccessKey'] as String? ?? '',
        awsSecretKey: j['awsSecretKey'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'captionModel': captionModel,
        'diaryModel': diaryModel,
        'baseUrl': baseUrl,
        'region': region,
        'awsAccessKey': awsAccessKey,
        'awsSecretKey': awsSecretKey,
      };
}

/// App-wide settings, stored as JSON next to the database.
class AppSettings {
  String provider;
  Map<String, ProviderConfig> providers;

  /// Auto diary at a fixed time (app must be running).
  bool diaryAuto;
  int diaryHour;
  int diaryMinute;
  String lastAutoDiaryDay;

  /// Capture interval in seconds.
  int captureIntervalSec;

  /// UI theme: 'system' | 'light' | 'dark'.
  String themeMode;

  /// Screenshot retention in days. 0 = keep forever. Diary rows are kept.
  int shotRetentionDays;

  /// Monitor device names to record (e.g. `\\.\DISPLAY1`).
  /// Empty = all connected monitors. Only currently-connected screens apply;
  /// screens added mid-capture are never included.
  List<String> selectedMonitors;

  AppSettings({
    this.provider = Providers.ollama,
    Map<String, ProviderConfig>? providers,
    this.diaryAuto = false,
    this.diaryHour = 23,
    this.diaryMinute = 0,
    this.lastAutoDiaryDay = '',
    this.captureIntervalSec = 10,
    this.themeMode = 'system',
    this.shotRetentionDays = 30,
    List<String>? selectedMonitors,
  })  : providers = providers ?? _defaults(),
        selectedMonitors = selectedMonitors ?? [];

  static ThemeMode parseTheme(String v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Map<String, ProviderConfig> _defaults() => {
        Providers.ollama: ProviderConfig(
          captionModel: 'qwen2.5vl:3b',
          diaryModel: 'qwen3:8b',
          baseUrl: 'http://127.0.0.1:11434',
        ),
        Providers.openai: ProviderConfig(
          captionModel: 'gpt-4o-mini',
          diaryModel: 'gpt-4o',
          baseUrl: 'https://api.openai.com/v1',
        ),
        Providers.openrouter: ProviderConfig(
          captionModel: 'anthropic/claude-3.5-haiku',
          diaryModel: 'anthropic/claude-3.5-sonnet',
          baseUrl: 'https://openrouter.ai/api/v1',
        ),
        Providers.anthropic: ProviderConfig(
          captionModel: 'claude-3-5-haiku-20241022',
          diaryModel: 'claude-3-5-sonnet-20241022',
        ),
        Providers.bedrock: ProviderConfig(
          captionModel: 'amazon.nova-lite-v1:0',
          diaryModel: 'anthropic.claude-3-5-sonnet-20241022-v2:0',
          region: 'us-east-1',
        ),
        Providers.gemini: ProviderConfig(
          captionModel: 'gemini-2.0-flash',
          diaryModel: 'gemini-2.5-flash',
        ),
      };

  ProviderConfig get active => providers[provider] ?? ProviderConfig();

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final s = AppSettings(
      provider: j['provider'] as String? ?? Providers.ollama,
      diaryAuto: j['diaryAuto'] as bool? ?? false,
      diaryHour: j['diaryHour'] as int? ?? 23,
      diaryMinute: j['diaryMinute'] as int? ?? 0,
      lastAutoDiaryDay: j['lastAutoDiaryDay'] as String? ?? '',
      captureIntervalSec: j['captureIntervalSec'] as int? ?? 10,
      themeMode: j['themeMode'] as String? ?? 'system',
      shotRetentionDays: j['shotRetentionDays'] as int? ?? 30,
      selectedMonitors: [
        for (final v in (j['selectedMonitors'] as List<dynamic>? ?? []))
          if (v is String) v,
      ],
    );
    final pj = j['providers'] as Map<String, dynamic>?;
    if (pj != null) {
      for (final e in pj.entries) {
        if (s.providers.containsKey(e.key) && e.value is Map) {
          s.providers[e.key] = ProviderConfig.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          );
        }
      }
    }
    if (s.captureIntervalSec < 5) s.captureIntervalSec = 5;
    if (s.captureIntervalSec > 300) s.captureIntervalSec = 300;
    return s;
  }

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'diaryAuto': diaryAuto,
        'diaryHour': diaryHour,
        'diaryMinute': diaryMinute,
        'lastAutoDiaryDay': lastAutoDiaryDay,
        'captureIntervalSec': captureIntervalSec,
        'themeMode': themeMode,
        'shotRetentionDays': shotRetentionDays,
        'selectedMonitors': selectedMonitors,
        'providers': {for (final e in providers.entries) e.key: e.value.toJson()},
      };

  static Future<Directory> _dir([Directory? override]) async {
    if (override != null) return override;
    return getApplicationSupportDirectory();
  }

  static Future<AppSettings> load({Directory? dir}) async {
    try {
      final d = await _dir(dir);
      final f = File(p.join(d.path, 'settings.json'));
      if (!await f.exists()) return AppSettings();
      final j = jsonDecode(await f.readAsString());
      if (j is Map<String, dynamic>) return AppSettings.fromJson(j);
      return AppSettings();
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save({Directory? dir}) async {
    final d = await _dir(dir);
    final f = File(p.join(d.path, 'settings.json'));
    await f.writeAsString(jsonEncode(toJson()));
  }
}
