// App smoke test: the app starts on the splash screen and opens Home.

import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('starts on the splash screen, then shows Home', (tester) async {
    await tester.pumpWidget(
      testApp(repository: FakeRoomRepository(), sockets: FakeSockets()),
    );
    await tester.pump();
    expect(find.text('Dice Majlis'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pump(const Duration(seconds: 2)); // splash timer
    await tester.pumpAndSettle(); // page transition

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('PLAY LUDO'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
