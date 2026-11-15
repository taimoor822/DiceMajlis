// App smoke test: the app starts on the splash screen and opens Home.

import 'package:dice_majlis_app/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts on the splash screen, then shows Home', (tester) async {
    await tester.pumpWidget(const DiceMajlisApp());
    expect(find.text('🎲 Dice Majlis'), findsOneWidget);
    expect(find.text('CREATE ROOM'), findsNothing);

    await tester.pump(const Duration(seconds: 2)); // splash timer
    await tester.pump(const Duration(seconds: 1)); // page transition

    expect(find.text('CREATE ROOM'), findsOneWidget);
    expect(find.text('JOIN ROOM'), findsOneWidget);
  });
}
