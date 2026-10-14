import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vtt_app/main.dart';

void main() {
  testWidgets('VTT shell shows timeline title', (WidgetTester tester) async {
    await tester.pumpWidget(const VttApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('오늘 타임라인'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
