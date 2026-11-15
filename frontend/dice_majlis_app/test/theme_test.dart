import 'package:dice_majlis_app/core/l10n/generated/app_localizations.dart';
import 'package:dice_majlis_app/core/theme/app_theme.dart';
import 'package:dice_majlis_app/core/theme/majlis_colors.dart';
import 'package:dice_majlis_app/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, theme) in [
    ('dark', AppTheme.dark()),
    ('light', AppTheme.light()),
  ]) {
    testWidgets('Home builds in the $name theme', (tester) async {
      expect(theme.extension<MajlisColors>(), isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('CREATE ROOM'), findsOneWidget);
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
