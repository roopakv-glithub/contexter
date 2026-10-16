import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moscowt/main.dart';

void main() {
  testWidgets('project setup walks through all three steps', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: MoscowtShell()));
    expect(
      find.text('Welcome back — here’s what your companion can do.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Setup Project'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your project'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Create your agent'), findsOneWidget);

    await tester.tap(find.text('Pixel').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review and finish'), findsOneWidget);
    expect(find.textContaining('Pixel — concise'), findsOneWidget);

    await tester.tap(find.text('Create Agent'));
    await tester.pumpAndSettle();
    expect(
      find.text('Welcome back — here’s what your companion can do.'),
      findsOneWidget,
    );
  });
}
