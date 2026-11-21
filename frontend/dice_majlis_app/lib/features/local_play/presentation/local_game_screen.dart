import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../ludo/domain/engine/ludo_engine.dart';
import '../../ludo/presentation/widgets/dice_widget.dart';
import '../../ludo/presentation/widgets/ludo_board_view.dart';
import '../domain/local_game_controller.dart';
import '../domain/local_game_setup.dart';
import '../domain/local_play_providers.dart';
import 'local_names.dart';

/// An offline game on this phone: people take turns on the same screen
/// (pass-and-play) and the Majlis AI plays its seats. Runs on the Dart engine;
/// nothing is sent to the server and nothing is saved.
class LocalGameScreen extends ConsumerStatefulWidget {
  const LocalGameScreen({super.key});

  @override
  ConsumerState<LocalGameScreen> createState() => _LocalGameScreenState();
}

class _LocalGameScreenState extends ConsumerState<LocalGameScreen> {
  LocalGameController? _game;
  bool _resultsShown = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    final setup = ref.read(localGameSetupProvider);
    if (setup == null) {
      // Opened without picking players (e.g. a refreshed page): pick first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.localPlay);
      });
      return;
    }
    _startGame(setup).start();
  }

  /// A fresh game for [setup]; call `start()` on it once it is in place.
  LocalGameController _startGame(LocalGameSetup setup) {
    _game?.removeListener(_onGameChanged);
    _game?.dispose();
    _resultsShown = false;
    final game = LocalGameController(
      setup: setup,
      dice: ref.read(localDiceProvider),
      timing: ref.read(localPlayTimingProvider),
    )..addListener(_onGameChanged);
    _game = game;
    return game;
  }

  void _onGameChanged() {
    final game = _game;
    if (game == null || _resultsShown) return;
    if (game.state.isFinished && !game.busy) {
      _resultsShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showResults(game);
      });
    }
  }

  @override
  void dispose() {
    _game?.removeListener(_onGameChanged);
    _game?.dispose();
    super.dispose();
  }

  String _name(LocalGameController game, int playerIndex) =>
      localPlayerName(_l10n, game.setup, game.state.players[playerIndex].seat);

  String _status(LocalGameController game) {
    final l10n = _l10n;
    final state = game.state;
    if (state.isFinished && !game.busy) {
      final winner = state.indexOf(state.winnerId!);
      return game.setup.humanCount == 1 &&
              game.kindOf(winner) == LocalSeatKind.human
          ? l10n.gameOverWon
          : l10n.localWinner(_name(game, winner));
    }
    final index = game.activePlayerIndex;
    final name = _name(game, index);
    if (game.kindOf(index) == LocalSeatKind.ai) return l10n.localStatusAi(name);
    if (game.busy) return l10n.gameMoving;
    final onlyYou = game.setup.humanCount == 1;
    if (state.phase == TurnPhase.awaitingRoll) {
      return onlyYou ? l10n.localStatusYourRoll : l10n.localStatusRoll(name);
    }
    return onlyYou ? l10n.localStatusYourMove : l10n.localStatusMove(name);
  }

  /// What just happened (no moves, a capture…), or null.
  String? _noticeText(LocalGameController game) {
    final notice = game.notice;
    if (notice == null) return null;
    final l10n = _l10n;
    final name = _name(game, notice.playerIndex);
    return switch (notice.kind) {
      LocalNoticeKind.noMoves => l10n.localNoticeNoMoves(name),
      LocalNoticeKind.tooManySixes => l10n.localNoticeTooManySixes(name),
      LocalNoticeKind.captured => l10n.localNoticeCaptured(name),
      LocalNoticeKind.home => l10n.localNoticeHome(name, notice.place!),
    };
  }

  Future<void> _confirmLeave() async {
    final game = _game;
    if (game == null || game.state.isFinished) {
      if (mounted) context.pop();
      return;
    }
    final l10n = _l10n;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.localLeaveTitle),
        content: Text(l10n.localLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.gameLeaveConfirm),
          ),
        ],
      ),
    );
    if (leave == true && mounted) context.pop();
  }

  Future<void> _showResults(LocalGameController game) async {
    final l10n = _l10n;
    final standings = game.standings;
    final again = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.localResultsTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status(game)),
            const SizedBox(height: 12),
            for (final row in standings)
              _StandingRow(
                place: row['place']! as int,
                name: _name(
                  game,
                  game.state.indexOf(row['player_id']! as String),
                ),
                color: game.state.player(row['player_id']! as String).color,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.localDone),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.localPlayAgain),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (again == true) {
      late LocalGameController next;
      setState(() => next = _startGame(game.setup));
      next.start();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    if (game == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final l10n = _l10n;
    // Your own dice and board skins, when signed in (offline: the plain ones).
    final skins = ref.watch(
      accountProvider.select(
        (account) => (dice: account?.diceSkin, board: account?.boardSkin),
      ),
    );

    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final state = game.state;
        final theme = Theme.of(context);
        final notice = _noticeText(game);
        final movable = game.movableTokens;
        final tokens = <BoardToken>[
          for (var i = 0; i < state.players.length; i++)
            for (var t = 0; t < state.players[i].tokens.length; t++)
              BoardToken(
                color: state.players[i].color,
                tokenIndex: t,
                progress: game.shownProgress(i, t),
                movable: i == state.currentIndex && movable.contains(t),
                dimmed:
                    movable.isNotEmpty &&
                    i == state.currentIndex &&
                    !movable.contains(t),
                flashing: game.isFlashing(i, t),
                onTap: () => game.moveToken(t),
              ),
        ];

        Widget panel(int seat) {
          final index = state.players.indexWhere((p) => p.seat == seat);
          if (index < 0) return const Expanded(child: SizedBox());
          final player = state.players[index];
          return Expanded(
            child: _SeatPanel(
              name: _name(game, index),
              color: player.color,
              isAi: game.kindOf(index) == LocalSeatKind.ai,
              isTurn: !state.isFinished && index == game.activePlayerIndex,
              place: player.finishPlace,
              alignEnd: seat == 2 || seat == 3,
            ),
          );
        }

        return PopScope(
          canPop: state.isFinished,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              title: Text(l10n.localGameTitle),
              actions: [
                IconButton(
                  tooltip: l10n.gameLeave,
                  icon: const Icon(Icons.exit_to_app),
                  onPressed: _confirmLeave,
                ),
              ],
            ),
            body: MajlisBackground(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Column(
                        children: [
                          // Panels sit next to their colour's base corner.
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    panel(1),
                                    const SizedBox(width: 8),
                                    panel(2),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Flexible(
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: LudoBoardView(
                                      tokens: tokens,
                                      stepDuration: game.timing.step,
                                      boardSkin: skins.board,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    panel(0),
                                    const SizedBox(width: 8),
                                    panel(3),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (notice != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          notice,
                                          key: const ValueKey('local-notice'),
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: context.majlis.gold,
                                              ),
                                        ),
                                      ),
                                    Text(
                                      _status(game),
                                      key: const ValueKey('local-status'),
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              DiceWidget(
                                key: const ValueKey('local-dice'),
                                value: game.diceValue,
                                enabled: game.canRoll,
                                onTap: game.roll,
                                skin: skins.dice,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeatPanel extends StatelessWidget {
  const _SeatPanel({
    required this.name,
    required this.color,
    required this.isAi,
    required this.isTurn,
    required this.place,
    required this.alignEnd,
  });

  final String name;
  final String color;
  final bool isAi;
  final bool isTurn;
  final int? place;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    final seatColor = MajlisColors.seatColor(color);
    final l10n = AppLocalizations.of(context);

    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: majlis.scrim.withValues(alpha: isTurn ? 0.35 : 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTurn ? seatColor : majlis.glassBorder,
            width: isTurn ? 2 : 1,
          ),
          boxShadow: isTurn
              ? [
                  BoxShadow(
                    color: seatColor.withValues(alpha: 0.5),
                    blurRadius: 14,
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: seatColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            if (isAi) ...[
              Icon(Icons.smart_toy_outlined, size: 16, color: majlis.textMuted),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (place != null) ...[
              const SizedBox(width: 6),
              Text(
                l10n.localPlaceShort(place!),
                style: TextStyle(
                  color: majlis.gold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.place,
    required this.name,
    required this.color,
  });

  final int place;
  final String name;
  final String color;

  @override
  Widget build(BuildContext context) {
    final majlis = context.majlis;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: MajlisColors.seatColor(color),
            child: Text(
              '$place',
              style: TextStyle(
                color: majlis.onSeat,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name)),
        ],
      ),
    );
  }
}
