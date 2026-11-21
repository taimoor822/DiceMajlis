import 'package:dice_majlis_app/core/auth/auth_controller.dart';
import 'package:dice_majlis_app/core/l10n/generated/app_localizations.dart';
import 'package:dice_majlis_app/core/theme/app_theme.dart';
import 'package:dice_majlis_app/core/theme/majlis_colors.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:dice_majlis_app/features/multiplayer/data/room_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

void main() {
  for (final (name, theme) in [
    ('dark', AppTheme.dark()),
    ('light', AppTheme.light()),
  ]) {
    testWidgets('Home builds in the $name theme', (tester) async {
      expect(theme.extension<MajlisColors>(), isNotNull);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWithValue(testAccount),
            ...fakeEconomy(),
            // Home also loads room invites.
            roomRepositoryProvider.overrideWithValue(FakeRoomRepository()),
          ],
          child: MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('PLAY LUDO'), findsOneWidget);
      expect(find.text('Player ID 123 456 789'), findsOneWidget);
    });
  }

  test('seat colours: known seats differ, unknown falls back', () {
    final seats = [
      'red',
      'blue',
      'green',
      'yellow',
    ].map(MajlisColors.seatColor);
    expect(seats.toSet(), hasLength(4));
    expect(MajlisColors.seatColor('RED'), MajlisColors.seatColor('red'));
    expect(MajlisColors.seatColor(null), isNotNull);
  });
}
