import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vtt_app/main.dart';

void main() {
  testWidgets('app bar shows movie/book/settings icons',
      (WidgetTester tester) async {
    await tester.pumpWidget(const VttApp());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byIcon(Icons.book_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.checklist_outlined), findsOneWidget);
  });
}
