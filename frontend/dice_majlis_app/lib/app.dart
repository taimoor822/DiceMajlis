import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/country_names.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_controller.dart';
import 'core/ui/messenger.dart';
import 'features/achievements/data/achievements_repository.dart';
import 'features/profile/domain/account_live.dart';
import 'features/rewards/presentation/reward_view.dart';

/// Root widget: Majlis themes, router and translations.
class DiceMajlisApp extends ConsumerWidget {
  const DiceMajlisApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the account's level and cosmetics live (it never rebuilds this).
    ref.watch(accountLiveProvider);
    final messenger = ref.watch(rootMessengerKeyProvider);
    // A note for every achievement unlocked while the app is open.
    ref.listen(achievementUnlocksProvider, (before, now) {
      final state = messenger.currentState;
      final context = messenger.currentContext;
      final grew = now.length > (before?.length ?? 0);
      if (state == null || context == null || !grew) return;
      final unlocked = now.last;
      final l10n = AppLocalizations.of(context);
      final reward = describeReward(context, unlocked.reward);
      state.showSnackBar(
        SnackBar(
          key: ValueKey('achievement-toast-${unlocked.code}-${unlocked.tier}'),
          content: Text(
            [l10n.achievementUnlockedToast(unlocked.name), reward]
                .where((part) => part.isNotEmpty)
                .join(' · '),
          ),
        ),
      );
    });
    return MaterialApp.router(
      scaffoldMessengerKey: messenger,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        CountryNamesDelegate(), // country names in the app's language
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
