import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../core/websocket/socket_providers.dart';
import '../../../core/websocket/socket_service.dart';
import '../../../shared/widgets/majlis_background.dart';
import '../../../shared/widgets/majlis_button.dart';
import '../../../shared/widgets/majlis_card.dart';
import '../data/room_repository.dart';
import '../domain/room_session.dart';
import '../domain/room_session_controller.dart';

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
  bool _starting = false;

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
    socket.connect(session.roomCode);
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
        case 'game_started':
          context.pushReplacement(AppRoutes.game(widget.roomCode));
      }
    } catch (e) {
      debugPrint('Lobby socket parse error: $e');
    }
  }

  Future<void> _startGame() async {
    final session = _session;
    if (session == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _starting = true);
    try {
      // The server answers on the socket with `game_started`.
      await ref.read(roomRepositoryProvider).startGame(session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.waitingRoomStartFailed)));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _copyCode() async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: widget.roomCode));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.waitingRoomCopied)));
  }

  @override
  void dispose() {
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

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final majlis = context.majlis;
    final seats = session.maxPlayers;
    final emptySeats = seats == null
        ? 0
        : (seats - _players.length).clamp(0, seats);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(l10n.waitingRoomTitle)),
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
                const SizedBox(height: 24),
                Text(
                  l10n.waitingRoomPlayers,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      for (final player in _players)
                        _PlayerTile(
                          player: player,
                          isMe: player.id == session.playerId,
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
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (session.isHost)
                  MajlisButton(
                    label: l10n.waitingRoomStart,
                    icon: Icons.play_arrow_rounded,
                    loading: _starting,
                    onPressed: _starting ? null : _startGame,
                  )
                else
                  Text(
                    l10n.waitingRoomWaitingForHost,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: majlis.textMuted,
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

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.isMe});

  final RoomPlayer player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = [
      if (isMe) l10n.waitingRoomYou,
      if (player.isHost) l10n.waitingRoomHost,
      if (player.isBot) l10n.waitingRoomBot,
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: MajlisColors.seatColor(player.color),
        child: Icon(
          player.isBot ? Icons.smart_toy_outlined : Icons.person,
          color: Colors.white,
        ),
      ),
      title: Text(player.name),
      trailing: tags.isEmpty
          ? null
          : Wrap(
              spacing: 6,
              children: [
                for (final tag in tags)
                  Chip(label: Text(tag), visualDensity: VisualDensity.compact),
              ],
            ),
    );
  }
}
