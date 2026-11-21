import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../core/websocket/socket_providers.dart';
import '../../../core/websocket/socket_service.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../../games/game_registry.dart';
import '../data/room_repository.dart';
import '../domain/room_info.dart';
import '../domain/room_session.dart';
import '../domain/room_session_controller.dart';

/// A private room before its game (step 1.13): who is in, who is ready, the
/// rules, and the host's controls (start, lock, invite, remove, make host).
/// Everything here is the server's: the screen asks, the room channel answers
/// with `players_updated` and `room_updated`.
class WaitingRoomScreen extends ConsumerStatefulWidget {
  const WaitingRoomScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  ConsumerState<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends ConsumerState<WaitingRoomScreen> {
  SocketService? _socket;
  StreamSubscription<dynamic>? _subscription;
  RoomSession? _session;
  List<RoomPlayer> _players = const [];
  RoomInfo? _info;
  bool _starting = false;
  bool _leaving = false;
  bool _busy = false;

  /// Seconds left in the start countdown (from the server, then counted
  /// down here once a second; the server starts the game on its own clock).
  int? _secondsLeft;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final session = ref.read(roomSessionProvider);
    if (session == null || session.roomCode != widget.roomCode) {
      // The router guard normally prevents this; stay safe anyway.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.home);
      });
      return;
    }
    _session = session;
    if (session.self != null) _players = [session.self!];

    final socket = ref.read(socketServiceFactoryProvider)();
    socket.connect(session.roomCode, roomId: session.roomId);
    _socket = socket;
    _subscription = socket.stream.listen(
      _onSocketEvent,
      onError: (Object error) => debugPrint('Lobby socket error: $error'),
    );
  }

  void _onSocketEvent(dynamic event) {
    if (!mounted) return;
    try {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      switch (data['type']) {
        case 'players_updated':
          final list = (data['players'] as List)
              .map(
                (p) => RoomPlayer.fromJson(Map<String, dynamic>.from(p as Map)),
              )
              .toList();
          setState(() => _players = list);
        case 'room_updated':
          _applyRoom(RoomInfo.fromJson(data));
        case 'player_kicked':
          if (data['player_id']?.toString() == _session?.playerId) {
            _goAway(AppLocalizations.of(context).waitingRoomKicked);
          }
        case 'game_started':
          context.pushReplacement(AppRoutes.game(widget.roomCode));
      }
    } catch (e) {
      debugPrint('Lobby socket parse error: $e');
    }
  }

  void _applyRoom(RoomInfo info) {
    final session = _session;
    // The host role can move: the session follows the server.
    if (session != null && info.hostId != null) {
      final isHost = info.hostId == session.playerId;
      if (isHost != session.isHost) {
        final updated = session.copyWith(isHost: isHost);
        _session = updated;
        ref.read(roomSessionProvider.notifier).start(updated);
      }
    }
    _ticker?.cancel();
    _secondsLeft = null;
    final seconds = info.startsIn;
    if (info.status == RoomStatus.starting && seconds != null) {
      _secondsLeft = seconds;
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        final left = (_secondsLeft ?? 0) - 1;
        if (!mounted || left <= 0) timer.cancel();
        if (mounted) setState(() => _secondsLeft = left < 0 ? 0 : left);
      });
    }
    setState(() => _info = info);
  }

  bool get _isHost {
    final session = _session;
    if (session == null) return false;
    final hostId = _info?.hostId;
    return hostId != null ? hostId == session.playerId : session.isHost;
  }

  RoomPlayer? get _me {
    final id = _session?.playerId;
    for (final p in _players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Runs one room request; a refusal shows the server's reason.
  Future<bool> _ask(Future<void> Function(RoomRepository rooms) request) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await request(ref.read(roomRepositoryProvider));
      return true;
    } catch (e) {
      if (mounted) _showText(l10n.apiErrorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showText(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Leaves the screen for the Game Hub (removed, or the room is gone).
  void _goAway(String message) {
    _showText(message);
    ref.read(roomSessionProvider.notifier).clear();
    context.go(AppRoutes.hub);
  }

  Future<void> _startGame() async {
    final session = _session;
    if (session == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _starting = true);
    try {
      // The server answers on the socket: `room_updated` (the countdown),
      // then `game_started`.
      await ref.read(roomRepositoryProvider).startGame(session.roomCode);
    } catch (e) {
      if (!mounted) return;
      _showText(l10n.apiErrorText(e));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Gives the seat back (the host role passes on) and goes to the Game Hub.
  Future<void> _leave() async {
    final session = _session;
    if (session == null || _leaving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _leaving = true);
    try {
      await ref.read(roomRepositoryProvider).leaveRoom(session.roomCode);
    } catch (e) {
      if (!mounted) return;
      setState(() => _leaving = false);
      _showText(l10n.apiErrorText(e));
      return;
    }
    if (!mounted) return;
    ref.read(roomSessionProvider.notifier).clear();
    context.go(AppRoutes.hub);
  }

  Future<void> _copyCode() async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: widget.roomCode));
    if (!mounted) return;
    _showText(l10n.waitingRoomCopied);
  }

  Future<void> _invite() async {
    final l10n = AppLocalizations.of(context);
    final playerId = await showDialog<int>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    if (playerId == null || !mounted) return;
    final sent = await _ask(
      (rooms) => rooms.invitePlayer(widget.roomCode, playerId),
    );
    if (sent && mounted) _showText(l10n.waitingRoomInviteSent);
  }

  Future<void> _pickRule(RoomOptionChoice option, GameModule module) async {
    final current = _info?.options[option.key] ?? option.defaultValue;
    final picked = await showModalBottomSheet<_Picked>(
      context: context,
      builder: (sheetContext) {
        final l10n = AppLocalizations.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  module.ruleName(l10n, option.key) ?? option.key,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in option.choices)
                      ChoiceChip(
                        label: Text(module.ruleValue(l10n, option.key, choice)),
                        selected: choice == current,
                        onSelected: (_) =>
                            Navigator.of(sheetContext).pop(_Picked(choice)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || picked.value == current || !mounted) return;
    final options = {...?_info?.options, option.key: picked.value};
    await _ask((rooms) => rooms.changeRules(widget.roomCode, options));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _subscription?.cancel();
    _socket?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Back (button or gesture) leaves the room on the server too.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: _page(context, session),
    );
  }

  Widget _page(BuildContext context, RoomSession session) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final info = _info;
    final isHost = _isHost;
    final seats = info?.maxPlayers ?? session.maxPlayers;
    final emptySeats = seats == null
        ? 0
        : (seats - _players.length).clamp(0, seats);
    final module = ref.watch(gameModulesProvider)[session.gameType];
    final status = info?.status ?? RoomStatus.unknown;
    final secondsLeft = _secondsLeft;
    final locked = info?.isLocked ?? false;
    final canInvite = !locked || isHost;

    final statusText = switch (status) {
      RoomStatus.starting when secondsLeft != null =>
        l10n.waitingRoomStartingIn(secondsLeft),
      RoomStatus.ready when _players.where((p) => !p.isBot).length < 2 =>
        l10n.waitingRoomStatusAlone,
      RoomStatus.ready => l10n.waitingRoomStatusReady,
      RoomStatus.waiting => l10n.waitingRoomStatusWaiting,
      _ => null,
    };

    final rules = [
      if (module != null && info != null)
        for (final option in info.optionChoices)
          if (module.ruleName(l10n, option.key) != null) option,
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(l10n.waitingRoomTitle),
        leading: IconButton(
          tooltip: l10n.waitingRoomLeave,
          icon: const Icon(Icons.close),
          onPressed: _leaving ? null : _leave,
        ),
        actions: [
          if (isHost)
            IconButton(
              tooltip: locked ? l10n.waitingRoomUnlock : l10n.waitingRoomLock,
              icon: Icon(
                locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: locked ? majlis.gold : null,
              ),
              onPressed: _busy || status == RoomStatus.starting
                  ? null
                  : () => _ask(
                      (rooms) =>
                          rooms.lockRoom(widget.roomCode, locked: !locked),
                    ),
            ),
          if (canInvite)
            IconButton(
              tooltip: l10n.waitingRoomInvite,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: _busy ? null : _invite,
            ),
        ],
      ),
      body: MajlisBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MajlisCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.waitingRoomCodeLabel,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: majlis.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              widget.roomCode,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: majlis.gold,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 6,
                              ),
                            ),
                            if (locked) ...[
                              const SizedBox(height: 4),
                              Text(
                                l10n.waitingRoomLocked,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: majlis.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.waitingRoomCopy,
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: _copyCode,
                      ),
                    ],
                  ),
                ),
                if (statusText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: status == RoomStatus.starting
                          ? majlis.gold
                          : majlis.textMuted,
                      fontWeight: status == RoomStatus.starting
                          ? FontWeight.w700
                          : null,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  l10n.waitingRoomPlayers,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final player in _players)
                        _PlayerTile(
                          player: player,
                          isMe: player.id == session.playerId,
                          isHost:
                              player.id == (info?.hostId ?? '') ||
                              (info?.hostId == null && player.isHost),
                          hostControls:
                              isHost &&
                              player.id != session.playerId &&
                              !player.isBot &&
                              status != RoomStatus.starting &&
                              !_busy,
                          onMakeHost: () => _ask(
                            (rooms) =>
                                rooms.transferHost(widget.roomCode, player.id),
                          ),
                          onRemove: () => _ask(
                            (rooms) =>
                                rooms.kickPlayer(widget.roomCode, player.id),
                          ),
                        ),
                      for (var i = 0; i < emptySeats; i++)
                        ListTile(
                          leading: Icon(
                            Icons.person_outline,
                            color: majlis.textMuted,
                          ),
                          title: Text(
                            l10n.waitingRoomEmptySeat,
                            style: TextStyle(color: majlis.textMuted),
                          ),
                        ),
                      if (rules.isNotEmpty && module != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.waitingRoomRules,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (isHost)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l10n.waitingRoomRulesHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: majlis.textMuted,
                              ),
                            ),
                          ),
                        for (final option in rules)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(module.ruleName(l10n, option.key)!),
                            trailing: Text(
                              module.ruleValue(
                                l10n,
                                option.key,
                                info?.options[option.key] ??
                                    option.defaultValue,
                              ),
                              style: TextStyle(color: majlis.gold),
                            ),
                            onTap:
                                isHost &&
                                    !_busy &&
                                    status != RoomStatus.starting
                                ? () => _pickRule(option, module)
                                : null,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isHost)
                  MajlisButton(
                    label: status == RoomStatus.starting && secondsLeft != null
                        ? l10n.waitingRoomStartingIn(secondsLeft)
                        : l10n.waitingRoomStart,
                    icon: Icons.play_arrow_rounded,
                    loading: _starting,
                    // Before the first room news the server decides.
                    onPressed:
                        _starting ||
                            status == RoomStatus.waiting ||
                            status == RoomStatus.starting
                        ? null
                        : _startGame,
                  )
                else if (info == null)
                  Text(
                    l10n.waitingRoomWaitingForHost,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: majlis.textMuted,
                    ),
                  )
                else if (_me?.isReady ?? false)
                  MajlisButton(
                    label: l10n.waitingRoomUnready,
                    icon: Icons.close_rounded,
                    style: MajlisButtonStyle.secondary,
                    loading: _busy,
                    onPressed: _busy
                        ? null
                        : () => _ask(
                            (rooms) =>
                                rooms.setReady(widget.roomCode, ready: false),
                          ),
                  )
                else
                  MajlisButton(
                    label: l10n.waitingRoomReady,
                    icon: Icons.check_rounded,
                    loading: _busy,
                    onPressed: _busy
                        ? null
                        : () => _ask(
                            (rooms) =>
                                rooms.setReady(widget.roomCode, ready: true),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A picked rule value (null is a value too, so it needs a box).
class _Picked {
  const _Picked(this.value);
  final Object? value;
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.isMe,
    required this.isHost,
    required this.hostControls,
    required this.onMakeHost,
    required this.onRemove,
  });

  final RoomPlayer player;
  final bool isMe;
  final bool isHost;

  /// The host may remove this player or pass them the host role.
  final bool hostControls;
  final VoidCallback onMakeHost;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final majlis = context.majlis;
    final tags = [
      if (isMe) l10n.playerTagYou,
      if (isHost) l10n.playerTagHost,
      if (player.isBot) l10n.playerTagBot,
    ];
    final ready = isHost || player.isBot || player.isReady;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: MajlisColors.seatColor(player.color),
        child: Icon(
          player.isBot ? Icons.smart_toy_outlined : Icons.person,
          color: majlis.onSeat,
        ),
      ),
      title: Text(player.name),
      subtitle: isHost || player.isBot
          ? null
          : Text(
              ready
                  ? l10n.waitingRoomPlayerReady
                  : l10n.waitingRoomPlayerNotReady,
              style: TextStyle(color: ready ? majlis.gold : majlis.textMuted),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tags.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                for (final tag in tags)
                  Chip(label: Text(tag), visualDensity: VisualDensity.compact),
              ],
            ),
          if (hostControls)
            PopupMenuButton<String>(
              tooltip: l10n.waitingRoomPlayerMenu,
              onSelected: (choice) =>
                  choice == 'host' ? onMakeHost() : onRemove(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'host',
                  child: Text(l10n.waitingRoomMakeHost),
                ),
                PopupMenuItem(
                  value: 'kick',
                  child: Text(l10n.waitingRoomRemove),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Asks for a friend's 9-digit Player ID.
class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final digits = _controller.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{9}$').hasMatch(digits)) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(int.parse(digits));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.waitingRoomInvite),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d ]'))],
        decoration: InputDecoration(
          hintText: l10n.waitingRoomInviteHint,
          errorText: _invalid ? l10n.waitingRoomInviteInvalid : null,
        ),
        onSubmitted: (_) => _send(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.waitingRoomCancel),
        ),
        TextButton(onPressed: _send, child: Text(l10n.waitingRoomInviteSend)),
      ],
    );
  }
}
