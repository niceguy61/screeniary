import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_app/capture_service.dart';
import 'package:vtt_app/settings_page.dart';

void main() {
  const channel =
      MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        final dir =
            await Directory.systemTemp.createTemp('vtt_test_');
        return dir.path;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('feedback button shows coming-soon without URL',
      (WidgetTester tester) async {
    final svc = CaptureService();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(svc: svc)),
      );
      // Real async zone: poll until lazy list builds the button.
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.text('피드백 보내기').evaluate().isNotEmpty) break;
      }
    });
    await tester.scrollUntilVisible(
      find.text('피드백 보내기'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('피드백 보내기'), findsOneWidget);
    await tester.tap(find.text('피드백 보내기'));
    await tester.pump();
    expect(find.textContaining('준비 중'), findsOneWidget);
    svc.dispose();
  });
}
