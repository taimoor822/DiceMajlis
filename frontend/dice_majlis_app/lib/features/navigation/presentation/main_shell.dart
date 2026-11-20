import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';

/// The app's frame: the page of the current tab, with the bottom bar
/// Events · Game Hub · Battle · Chat · Social. Battle, in the centre, is the
/// Home lobby where the app opens. Each tab keeps its own history, so
/// switching tabs and back returns to where you were.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Battle: the Home lobby (must match the branch order in app_router.dart).
  static const homeIndex = 2;

  void _select(int index) => navigationShell.goBranch(
    index,
    // Tapping the tab you're already on goes back to its first page.
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onHome = navigationShell.currentIndex == homeIndex;

    return PopScope(
      // Back on another tab returns to the lobby first; back there leaves
      // the app.
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !onHome) _select(homeIndex);
      },
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _select,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.celebration_outlined),
              selectedIcon: const Icon(Icons.celebration),
              label: l10n.navEvents,
            ),
            NavigationDestination(
              icon: const Icon(Icons.casino_outlined),
              selectedIcon: const Icon(Icons.casino),
              label: l10n.navGameHub,
            ),
            NavigationDestination(
              icon: const Icon(Icons.bolt_outlined),
              selectedIcon: const Icon(Icons.bolt),
              label: l10n.navBattle,
            ),
            NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: l10n.navChat,
            ),
            NavigationDestination(
              icon: const Icon(Icons.people_outline),
              selectedIcon: const Icon(Icons.people),
              label: l10n.navSocial,
            ),
          ],
        ),
      ),
    );
  }
}
