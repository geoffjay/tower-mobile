// Smoke test: the app boots to the Machines screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tower_mobile/main.dart';

void main() {
  testWidgets('app boots to the machines screen', (tester) async {
    // Plugin mock: the registry loads SharedPreferences at boot.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TowerMobileApp());
    // Fixed pumps, not pumpAndSettle: the shell holds a persistent
    // stream (session state) that never "settles".
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    // Boot completed: the shell renders (app bar title + nav label).
    expect(find.text('Machines'), findsAtLeastNWidgets(1));
  });
}
