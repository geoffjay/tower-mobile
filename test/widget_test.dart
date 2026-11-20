// Behavioral widget tests for the 4-tab shell, host switcher sheet,
// and unconfigured-host setup flow.
library;

import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tower_mobile/main.dart';

void main() {
  testWidgets('boots to Fleet with 4 spacious tabs and host setup CTA', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TowerMobileApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // 4 primary operational tabs render with no layout overflow.
    expect(find.text('Fleet'), findsAtLeastNWidgets(2));
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Jobs'), findsOneWidget);
    expect(find.text('Workflows'), findsOneWidget);

    // Unconfigured empty state offers direct host setup CTA.
    expect(find.text('No tower host configured'), findsOneWidget);
    expect(find.text('Add tower host'), findsOneWidget);

    // Tapping the app-bar host chip opens the Tower hosts sheet.
    await tester.tap(find.text('Add host'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Tower hosts'), findsOneWidget);
  });

  testWidgets('saved host renders Connect CTA and two-press host removal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'machines': jsonEncode([
        {
          'id': 'm1',
          'name': 'kobo',
          'host': 'kobo.tailnet.ts.net',
          'port': 22,
          'username': 'kobo',
          'host_key_fingerprint': '',
          'key_bootstrapped': false,
        },
      ]),
      'active_machine': 'm1',
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TowerMobileApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Disconnected from kobo'), findsOneWidget);
    expect(find.text('Connect kobo'), findsOneWidget);

    // Open Switch host sheet -> verify host appears and two-press remove works.
    await tester.tap(find.text('Switch host'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Tower hosts'), findsOneWidget);
    expect(find.byTooltip('Remove host'), findsOneWidget);

    // First tap arms removal without deleting.
    await tester.tap(find.byTooltip('Remove host'));
    await tester.pump();
    expect(find.byTooltip('Confirm remove'), findsOneWidget);

    // After 3 seconds without a second tap, armed state resets safely.
    await tester.pump(const Duration(seconds: 3, milliseconds: 100));
    expect(find.byTooltip('Remove host'), findsOneWidget);
  });
}
