import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/api_error_text.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/realtime_providers.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/majlis_colors.dart';
import '../../../core/websocket/socket_providers.dart';
import '../../../core/websocket/socket_service.dart';
import '../../games/domain/game_catalog.dart';
import '../../multiplayer/data/room_repository.dart';
import '../../multiplayer/domain/room_session.dart';
import '../../multiplayer/domain/room_session_controller.dart';
import '../domain/ludo_path.dart';
import '../domain/turn_clock.dart';

// Widgets
import 'widgets/board_widget.dart';
import 'widgets/dice_widget.dart';
import 'widgets/player_token.dart';

class GameBoardScreen extends ConsumerStatefulWidget {
  const GameBoardScreen({super.key, required this.roomCode});

  final String roomCode;

  @override
  ConsumerState<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _PlayerInfo {
  final String id;
  final String name;
  final String color;
  final bool isHost;
  final bool isBot;

  /// False while the player has no live connection (their seat is kept).
  final bool connected;

  const _PlayerInfo({
    required this.id,
    required this.name,
    required this.color,
    required this.isHost,
    required this.isBot,
    this.connected = true,
  });

  factory _PlayerInfo.fromJson(Map<String, dynamic> json) {
    return _PlayerInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      isHost: json['is_host'] == true,
      isBot: json['is_bot'] == true,
      connected: json['connected'] != false,
    );
  }

  _PlayerInfo withConnected(bool value) => _PlayerInfo(
    id: id,
    name: name,
    color: color,
    isHost: isHost,
    isBot: isBot,
    connected: value,
  );
}

/// Server sends progress 0..56 (56 = home). 100 is the pre-engine "home" value.
bool _isHomePosition(int position) =>
    position == 100 || position >= LudoPath.homeProgress;

class _TokenInfo {
  final String id;
  final String playerId;
  final int position;
  final bool isFinished;

  const _TokenInfo({
    required this.id,
    required this.playerId,
    required this.position,
    required this.isFinished,
  });

  _TokenInfo copyWith({int? position, bool? isFinished}) {
    final nextPosition = position ?? this.position;
    return _TokenInfo(
      id: id,
      playerId: playerId,
      position: nextPosition,
      isFinished:
          isFinished ?? this.isFinished || _isHomePosition(nextPosition),
    );
  }

  factory _TokenInfo.fromJson(Map<String, dynamic> json) {
    final position = (json['position'] as num?)?.toInt() ?? -1;
    return _TokenInfo(
      id: json['id']?.toString() ?? '',
      playerId: json['player_id']?.toString() ?? '',
      position: position,
      isFinished: json['is_finished'] == true || _isHomePosition(position),
    );
  }
}

class _GameBoardScreenState extends ConsumerState<GameBoardScreen> {
  late SocketService socket;
  bool _initialized = false;
  bool _socketConnected = false;
  StreamSubscription<dynamic>? _socketSubscription;

  String? roomCode;
  String? roomId;
  String? myPlayerId;
  bool _winnerShown = false;
  bool _winnerDialogOpen = false;
  bool _rematchOpened = false;

  String? currentTurnPlayerId;
  int? lastDice;

  /// Tokens the server says can move with [lastDice]; null until it tells us.
  Set<String>? _movableTokenIds;

  /// Display countdown for the current turn (the server owns the real timer).
  final TurnClock _turnClock = TurnClock();
  Timer? _turnClockTicker;

  bool _isRollingDice = false;
  bool _isAnimatingMove = false;
  bool _isReconnecting = false;
  ValueNotifier<RealtimeStatus>? _liveStatus;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  Future<void> _animationQueue = Future.value();
  final Set<String> _flashingTokenIds = {};

  final Map<String, _PlayerInfo> _playersById = {};
  final List<String> _playerOrder = [];
  final Map<String, _TokenInfo> _tokensById = {};

  Duration _moveStepDuration = const Duration(milliseconds: 140);
  int _syncVersion = 0;

  @override
  void initState() {
    super.initState();
    socket = ref.read(socketServiceFactoryProvider)();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final session = ref.read(roomSessionProvider);
    if (session == null || session.roomCode != widget.roomCode) {
      _redirectHome();
      return;
    }

    roomCode = session.roomCode;
    roomId = session.roomId;
    myPlayerId = session.playerId;

    _connectSocket();
    _liveStatus = ref.read(realtimeClientProvider)?.status
      ?..addListener(_onLiveStatus);
  }

  void _connectSocket() {
    final room = roomCode;
    if (room == null) return;

    _reconnectTimer?.cancel();
    _socketSubscription?.cancel();

    if (_socketConnected) {
      socket.disconnect();
      _socketConnected = false;
    }

    socket = ref.read(socketServiceFactoryProvider)();
    socket.connect(room, roomId: roomId);
    _socketConnected = true;

    _socketSubscription = socket.stream.listen(
      _handleSocketEvent,
      onError: (error) {
        debugPrint('Socket error: $error');
        _scheduleReconnect();
      },
      onDone: _scheduleReconnect,
    );
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    if (_isReconnecting) return;

    final room = roomCode;
    final me = myPlayerId;
    if (room == null || me == null) return;

    setState(() {
      _isReconnecting = true;
      _reconnectAttempts += 1;
    });

    if (_reconnectAttempts > 6) {
      setState(() {
        _isReconnecting = false;
      });
      return;
    }

    final delaySeconds = math.min(
      20,
      math.pow(2, _reconnectAttempts - 1).toInt(),
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) return;
      _connectSocket();
      if (!mounted) return;
      setState(() {
        _isReconnecting = false;
      });
    });
  }

  /// A player dropped (their seat is kept) or came back.
  void _applyConnection(String? playerId, {required bool connected}) {
    final player = _playersById[playerId];
    if (player == null || player.connected == connected) return;
    setState(() => _playersById[player.id] = player.withConnected(connected));
    if (player.id == myPlayerId) return;
    _showNotice(
      connected
          ? _l10n.gamePlayerReconnected(player.name)
          : _l10n.gamePlayerDisconnected(player.name),
    );
  }

  /// This phone's own live connection: while it is down the board waits
  /// (the server keeps the seat and the turn clock runs).
  void _onLiveStatus() {
    final status = _liveStatus;
    if (!mounted || status == null) return;
    final down = status.value != RealtimeStatus.online;
    if (down == _isReconnecting) return;
    setState(() => _isReconnecting = down);
  }

  @override
  void dispose() {
    _liveStatus?.removeListener(_onLiveStatus);
    _socketSubscription?.cancel();
    _reconnectTimer?.cancel();
    _turnClockTicker?.cancel();
    if (_socketConnected) {
      socket.disconnect();
    }
    super.dispose();
  }

  bool get isMyTurn =>
      myPlayerId != null &&
      currentTurnPlayerId != null &&
      myPlayerId == currentTurnPlayerId;

  bool _canMoveToken(_TokenInfo token) {
    final dice = lastDice;
    if (!isMyTurn || dice == null) return false;

    // Only the server knows the rules: it lists the tokens that may move
    // (in the roll response and the dice_rolled message). Until then, none.
    return _movableTokenIds?.contains(token.id) ?? false;
  }

  static Set<String>? _parseTokenIds(Object? ids) =>
      ids is List ? ids.map((id) => id.toString()).toSet() : null;

  /// Call inside setState. Reads `seconds_left` / `warning_seconds` from the server.
  void _startTurnClock(Map<String, dynamic> data) {
    _turnClock.start(
      (data['seconds_left'] as num?)?.toInt(),
      warningSeconds: (data['warning_seconds'] as num?)?.toInt(),
    );
    _turnClockTicker?.cancel();
    if (!_turnClock.isRunning) return;
    _turnClockTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (_turnClock.secondsLeft == 0) timer.cancel();
    });
  }

  void _stopTurnClock() {
    _turnClockTicker?.cancel();
    _turnClockTicker = null;
    _turnClock.stop();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  String _playerName(String? id) =>
      _playersById[id]?.name ?? _l10n.gameUnknownPlayer;

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPlayerTimedOut(Map<String, dynamic> data) {
    final id = data['player_id']?.toString();
    final missed = (data['missed_turns'] as num?)?.toInt() ?? 1;
    final limit = (data['max_missed_turns'] as num?)?.toInt() ?? 0;
    final left = limit - missed;
    if (limit > 0 && left <= 0) return; // a "removed" message follows
    if (id != null && id == myPlayerId) {
      _showNotice(
        limit > 0 ? _l10n.gameTimeoutSelfWarning(left) : _l10n.gameTimeoutSelf,
      );
    } else {
      _showNotice(_l10n.gameTimeoutOther(_playerName(id)));
    }
  }

  void _showPlayerRemoved(Map<String, dynamic> data) {
    final id = data['player_id']?.toString();
    final idle = data['reason']?.toString() == 'timeout';
    if (id != null && id == myPlayerId) {
      _showNotice(idle ? _l10n.gameRemovedSelfIdle : _l10n.gameLeftSelf);
    } else {
      final name = _playerName(id);
      _showNotice(
        idle ? _l10n.gameRemovedOtherIdle(name) : _l10n.gameLeftOther(name),
      );
    }
  }

  void _redirectHome() {
    // After the frame: providers can't change while widgets are building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(roomSessionProvider.notifier).clear();
      context.go(AppRoutes.home);
    });
  }

  void _handleSocketEvent(dynamic event) {
    if (!mounted) return;

    try {
      final raw = event is String ? event : utf8.decode(event as List<int>);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final data = Map<String, dynamic>.from(decoded);
      final type = data['type']?.toString();
      if (type == null) return;

      switch (type) {
        case 'game_started':
          _applyGameStarted(data);
          break;

        case 'players_updated':
          _applyPlayersUpdated(data);
          break;

        case 'dice_rolled':
          setState(() {
            lastDice = (data['dice'] as num?)?.toInt();
            _movableTokenIds = _parseTokenIds(data['movable_token_ids']);
            final rollerId = data['player_id']?.toString();
            if (rollerId != null && rollerId == myPlayerId) {
              _isRollingDice = false;
            }
          });
          break;

        case 'token_moved':
          _applyTokenMoved(data);
          break;

        case 'turn_changed':
          setState(() {
            currentTurnPlayerId = data['player_id']?.toString();
            lastDice = null;
            _movableTokenIds = null;
            _isRollingDice = false;
            _startTurnClock(data);
          });
          break;

        case 'player_timeout':
          _showPlayerTimedOut(data);
          break;

        case 'player_forfeited':
          _showPlayerRemoved(data);
          break;

        case 'player_disconnected':
        case 'player_reconnected':
          _applyConnection(
            data['player_id']?.toString(),
            connected: type == 'player_reconnected',
          );
          break;

        case 'rematch_started':
          _openRematch(
            roomCode: data['room_code']?.toString(),
            roomId: data['room_id']?.toString(),
            seatId: (data['seats'] is Map)
                ? (data['seats'] as Map)[myPlayerId]?.toString()
                : null,
          );
          break;

        case 'game_finished':
          setState(_stopTurnClock);
          final winnerId = data['winner_id']?.toString();
          if (winnerId != null) {
            _showWinner(winnerId);
          }
          break;
      }
    } catch (e) {
      debugPrint('Socket parse error: $e');
    }
  }

  void _applyGameStarted(Map<String, dynamic> data) {
    final players = data['players'];
    final tokens = data['tokens'];

    final nextPlayersById = <String, _PlayerInfo>{};
    final nextPlayerOrder = <String>[];
    if (players is List) {
      for (final p in players) {
        if (p is Map) {
          final info = _PlayerInfo.fromJson(Map<String, dynamic>.from(p));
          if (info.id.isNotEmpty) {
            nextPlayersById[info.id] = info;
            nextPlayerOrder.add(info.id);
          }
        }
      }
    }

    final nextTokensById = <String, _TokenInfo>{};
    if (tokens is List) {
      for (final t in tokens) {
        if (t is Map) {
          final token = _TokenInfo.fromJson(Map<String, dynamic>.from(t));
          if (token.id.isNotEmpty && token.playerId.isNotEmpty) {
            nextTokensById[token.id] = token;
          }
        }
      }
    }

    setState(() {
      _syncVersion += 1;
      _playersById
        ..clear()
        ..addAll(nextPlayersById);
      _playerOrder
        ..clear()
        ..addAll(nextPlayerOrder);
      _tokensById
        ..clear()
        ..addAll(nextTokensById);
      _flashingTokenIds.clear();
      currentTurnPlayerId = data['current_turn_player_id']?.toString();
      lastDice = (data['last_dice'] as num?)?.toInt();
      _movableTokenIds = _parseTokenIds(data['movable_token_ids']);
      _startTurnClock(data);
      _reconnectAttempts = 0;
      _isReconnecting = false;
      _isRollingDice = false;
      _isAnimatingMove = false;
      _moveStepDuration = const Duration(milliseconds: 140);
    });

    _animationQueue = Future.value();

    // Reconnected after the game ended.
    final winnerId = data['winner_id']?.toString();
    if (winnerId != null) {
      setState(_stopTurnClock);
      _showWinner(winnerId);
    }
  }

  void _applyPlayersUpdated(Map<String, dynamic> data) {
    final players = data['players'];
    if (players is! List) return;

    final nextPlayersById = <String, _PlayerInfo>{};
    final nextOrder = <String>[];
    for (final p in players) {
      if (p is Map) {
        final info = _PlayerInfo.fromJson(Map<String, dynamic>.from(p));
        if (info.id.isNotEmpty) {
          nextPlayersById[info.id] = info;
          nextOrder.add(info.id);
        }
      }
    }

    setState(() {
      _playersById.addAll(nextPlayersById);
      if (nextOrder.isNotEmpty) {
        _playerOrder
          ..clear()
          ..addAll(nextOrder);
      }
    });
  }

  void _applyTokenMoved(Map<String, dynamic> data) {
    final tokenId = data['token_id']?.toString();
    final from = (data['from'] as num?)?.toInt();
    final to = (data['to'] as num?)?.toInt();
    final dice = (data['dice'] as num?)?.toInt();
    if (tokenId == null || to == null) return;

    final killed = <String>[];
    final rawKilled = data['killed'];
    if (rawKilled is List) {
      for (final k in rawKilled) {
        final id = k?.toString();
        if (id != null && id.isNotEmpty) {
          killed.add(id);
        }
      }
    }

    final syncVersion = _syncVersion;
    _animationQueue = _animationQueue.then((_) {
      return _animateTokenMove(
        tokenId: tokenId,
        from: from,
        to: to,
        dice: dice,
        killedTokenIds: killed,
        syncVersion: syncVersion,
      );
    });
  }

  Future<void> _animateTokenMove({
    required String tokenId,
    required int? from,
    required int to,
    required int? dice,
    required List<String> killedTokenIds,
    required int syncVersion,
  }) async {
    if (!mounted || syncVersion != _syncVersion) return;

    final startToken = _tokensById[tokenId];
    if (startToken == null) return;

    final lastIndex = LudoPath.redPath.length - 1;

    int toUi;
    if (_isHomePosition(to)) {
      toUi = lastIndex;
    } else if (to < 0) {
      toUi = -1;
    } else {
      toUi = to.clamp(0, lastIndex);
    }

    final startRaw = from ?? startToken.position;
    int startUi;
    if (_isHomePosition(startRaw)) {
      startUi = lastIndex;
    } else if (startRaw < 0) {
      startUi = -1;
    } else {
      startUi = startRaw.clamp(0, lastIndex);
    }

    final steps = <int>[];
    if (toUi >= 0) {
      if (startUi < 0) {
        for (int p = 0; p <= toUi; p++) {
          steps.add(p);
        }
      } else {
        for (int p = startUi + 1; p <= toUi; p++) {
          steps.add(p);
        }
      }
    }

    setState(() {
      _isAnimatingMove = true;
    });

    final perStepMs = dice == null ? 140 : (180 - (dice * 15)).clamp(80, 160);
    final stepDelay = Duration(milliseconds: perStepMs);

    setState(() {
      _moveStepDuration = stepDelay;
    });

    for (final p in steps) {
      if (!mounted || syncVersion != _syncVersion) return;

      setState(() {
        final current = _tokensById[tokenId];
        if (current != null) {
          _tokensById[tokenId] = current.copyWith(position: p);
        }
      });

      await Future.delayed(stepDelay);
    }

    if (!mounted || syncVersion != _syncVersion) return;

    if (_isHomePosition(to)) {
      setState(() {
        final current = _tokensById[tokenId];
        if (current != null) {
          _tokensById[tokenId] = current.copyWith(
            position: LudoPath.homeProgress,
            isFinished: true,
          );
        }
      });
    }

    if (killedTokenIds.isNotEmpty) {
      setState(() {
        for (final killedId in killedTokenIds) {
          final killedToken = _tokensById[killedId];
          if (killedToken != null) {
            _tokensById[killedId] = killedToken.copyWith(
              position: -1,
              isFinished: false,
            );
            _flashingTokenIds.add(killedId);
          }
        }
      });

      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted || syncVersion != _syncVersion) return;
      setState(() {
        _flashingTokenIds.removeAll(killedTokenIds);
      });
    }

    if (!mounted || syncVersion != _syncVersion) return;

    setState(() {
      lastDice = null;
      _movableTokenIds = null;
      _isAnimatingMove = false;
    });
  }

  Future<void> _rollDice() async {
    final room = roomCode;
    if (room == null || myPlayerId == null) return;
    if (_isReconnecting || _isAnimatingMove || _isRollingDice) return;

    setState(() {
      _isRollingDice = true;
    });

    try {
      final result = await ref.read(roomRepositoryProvider).rollDice(room);
      // The dice_rolled message may have arrived first; it says the same.
      if (mounted && lastDice == null) {
        setState(() {
          lastDice = result.dice;
          _movableTokenIds = result.movableTokenIds.toSet();
          _isRollingDice = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRollingDice = false;
        });
      }
      _showNotice(_l10n.apiErrorText(e));
    }
  }

  Future<void> _moveToken(String tokenId) async {
    final room = roomCode;
    if (room == null || myPlayerId == null) return;
    if (_isReconnecting || _isAnimatingMove) return;

    try {
      await ref.read(roomRepositoryProvider).moveToken(room, tokenId);
    } catch (e) {
      _showNotice(_l10n.apiErrorText(e));
    }
  }

  String _pathColorForBackend(String color) {
    final c = color.trim().toLowerCase();
    if (c == 'orange') return 'yellow';
    if (c == 'amber') return 'yellow';
    return c;
  }

  int _seatForBackendColor(String color) {
    switch (_pathColorForBackend(color)) {
      case 'red':
        return 0;
      case 'yellow':
        return 1;
      case 'green':
        return 2;
      case 'blue':
        return 3;
      default:
        return 0;
    }
  }

  static const Map<String, List<math.Point<int>>> _baseGridByColor = {
    'red': <math.Point<int>>[
      math.Point<int>(1, 13),
      math.Point<int>(3, 13),
      math.Point<int>(1, 11),
      math.Point<int>(3, 11),
    ],
    'blue': <math.Point<int>>[
      math.Point<int>(1, 1),
      math.Point<int>(3, 1),
      math.Point<int>(1, 3),
      math.Point<int>(3, 3),
    ],
    'green': <math.Point<int>>[
      math.Point<int>(11, 1),
      math.Point<int>(13, 1),
      math.Point<int>(11, 3),
      math.Point<int>(13, 3),
    ],
    'yellow': <math.Point<int>>[
      math.Point<int>(11, 13),
      math.Point<int>(13, 13),
      math.Point<int>(11, 11),
      math.Point<int>(13, 11),
    ],
  };

  math.Point<int> _baseGridForToken(String pathColor, int tokenIndex) {
    final list = _baseGridByColor[pathColor] ?? _baseGridByColor['red']!;
    return list[tokenIndex % list.length];
  }

  int _uiIndexForToken(_TokenInfo token, int pathLength) {
    if (token.isFinished || _isHomePosition(token.position)) {
      return pathLength - 1;
    }
    if (token.position < 0) return -1;
    if (token.position >= pathLength) return pathLength - 1;
    return token.position;
  }

  math.Point<int> _gridForToken({
    required _TokenInfo token,
    required String pathColor,
    required int tokenIndex,
  }) {
    if (token.position < 0 && !token.isFinished) {
      return _baseGridForToken(pathColor, tokenIndex);
    }

    final path = LudoPath.getPath(pathColor);
    final idx = _uiIndexForToken(token, path.length);
    if (idx < 0) return _baseGridForToken(pathColor, tokenIndex);
    return path[idx];
  }

  Offset _spreadOffset(int index, int count, double radius) {
    if (count <= 1) return Offset.zero;
    final angle = (2 * math.pi) * (index / count);
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  Widget _buildPlayerPanel(_PlayerInfo player, int seat) {
    final isTurn = player.id == currentTurnPlayerId;
    final isMe = player.id == myPlayerId;
    final color = MajlisColors.seatColor(player.color);
    final majlis = context.majlis;

    final title = [
      player.name,
      if (player.isBot) _l10n.playerTagBot,
      if (isMe) _l10n.playerTagYou,
      if (!player.connected) _l10n.playerTagAway,
    ].join(' • ');

    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: majlis.scrim.withValues(alpha: isTurn ? 0.35 : 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTurn ? color : majlis.glassBorder,
          width: isTurn ? 2 : 1,
        ),
        boxShadow: isTurn
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 18,
                  spreadRadius: 1,
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

    final alignment = switch (seat % 4) {
      0 => Alignment.bottomCenter,
      1 => Alignment.centerRight,
      2 => Alignment.topCenter,
      _ => Alignment.centerLeft,
    };

    final offset = switch (seat % 4) {
      0 => const Offset(0, 74),
      1 => const Offset(74, 0),
      2 => const Offset(0, -74),
      _ => const Offset(-74, 0),
    };

    return Align(
      alignment: alignment,
      child: Transform.translate(offset: offset, child: panel),
    );
  }

  Widget _buildStatusChip() {
    final majlis = context.majlis;
    final turnText = currentTurnPlayerId == null
        ? _l10n.gameStatusSyncing
        : isMyTurn
        ? _l10n.gameStatusYourTurn
        : _l10n.gameStatusOpponentTurn;
    final secondsLeft = currentTurnPlayerId == null
        ? null
        : _turnClock.secondsLeft;
    final text = secondsLeft == null
        ? turnText
        : _l10n.gameStatusWithSeconds(turnText, secondsLeft);
    final hurry = isMyTurn && _turnClock.isWarning;

    final color = currentTurnPlayerId == null
        ? majlis.textMuted
        : hurry
        ? majlis.warning
        : isMyTurn
        ? majlis.success
        : majlis.danger;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: majlis.scrim.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: majlis.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: hurry ? majlis.warning : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Leaving a started game forfeits it, so ask first.
  Future<void> _confirmLeave() async {
    final room = roomCode;
    if (room == null || _winnerShown) return;
    final l10n = _l10n;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.gameLeaveTitle),
        content: Text(l10n.gameLeaveBody),
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
    if (leave != true || !mounted) return;
    try {
      await ref.read(roomRepositoryProvider).leaveRoom(room);
    } catch (e) {
      _showNotice(l10n.apiErrorText(e));
      return;
    }
    if (!mounted) return;
    _winnerShown = true; // no result dialog for a game we left
    ref.read(roomSessionProvider.notifier).clear();
    context.go(AppRoutes.home);
  }

  void _showWinner(String winnerId) {
    if (_winnerShown) return;
    _winnerShown = true;
    final me = myPlayerId;
    final room = roomCode;
    final l10n = _l10n;
    var asked = false;
    _winnerDialogOpen = true;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.gameOverTitle),
          content: Text(
            asked
                ? l10n.gameOverWaitingForOthers
                : me != null && winnerId == me
                ? l10n.gameOverWon
                : l10n.gameOverLost,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _goHomeAfterGame();
              },
              child: Text(l10n.gameOverHome),
            ),
            if (!asked && room != null)
              TextButton(
                onPressed: () async {
                  setDialogState(() => asked = true);
                  try {
                    final answer = await ref
                        .read(roomRepositoryProvider)
                        .rematch(room, want: true);
                    // The last one to say yes gets the new room right away.
                    if (answer.started) {
                      _openRematch(
                        roomCode: answer.roomCode,
                        roomId: answer.roomId,
                        seatId: answer.seatId,
                      );
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      setDialogState(() => asked = false);
                    }
                    _showNotice(l10n.apiErrorText(e));
                  }
                },
                child: Text(l10n.gameOverPlayAgain),
              ),
          ],
        ),
      ),
    ).whenComplete(() => _winnerDialogOpen = false);
  }

  /// Home after the game: the seat is given back, so nobody waits for a
  /// rematch answer from this player.
  void _goHomeAfterGame() {
    final room = roomCode;
    if (room != null) {
      unawaited(
        ref
            .read(roomRepositoryProvider)
            .leaveRoom(room)
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    ref.read(roomSessionProvider.notifier).clear();
    if (mounted) context.go(AppRoutes.home);
  }

  /// Everyone agreed: the rematch room, with this player's new seat.
  void _openRematch({String? roomCode, String? roomId, String? seatId}) {
    final session = ref.read(roomSessionProvider);
    if (!mounted || roomCode == null || seatId == null || _rematchOpened) {
      return;
    }
    _rematchOpened = true;
    if (_winnerDialogOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    ref
        .read(roomSessionProvider.notifier)
        .start(
          RoomSession(
            roomCode: roomCode,
            roomId: roomId,
            playerId: seatId,
            gameType: session?.gameType ?? GameChoice.ludo,
            variant: session?.variant ?? GameChoice.classic,
          ),
        );
    context.go(AppRoutes.room(roomCode));
  }

  @override
  Widget build(BuildContext context) {
    final room = roomCode;
    final me = myPlayerId;
    if (room == null || me == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tokensByPlayer = <String, List<_TokenInfo>>{};
    for (final t in _tokensById.values) {
      (tokensByPlayer[t.playerId] ??= []).add(t);
    }
    for (final entry in tokensByPlayer.entries) {
      entry.value.sort((a, b) => a.id.compareTo(b.id));
    }

    final tokenLabels = <String, String>{};
    final tokenIndexById = <String, int>{};
    for (final entry in tokensByPlayer.entries) {
      final tokens = entry.value;
      for (int i = 0; i < tokens.length; i++) {
        tokenIndexById[tokens[i].id] = i;
        tokenLabels[tokens[i].id] = '${i + 1}';
      }
    }

    final playersInSeat = List<_PlayerInfo?>.filled(4, null);
    for (final id in _playerOrder) {
      final info = _playersById[id];
      if (info == null) continue;
      final seat = _seatForBackendColor(info.color);
      if (seat >= 0 && seat < 4) {
        playersInSeat[seat] = info;
      }
    }

    final canRollDice =
        currentTurnPlayerId != null &&
        isMyTurn &&
        lastDice == null &&
        !_isRollingDice &&
        !_isAnimatingMove &&
        !_isReconnecting;

    final majlis = context.majlis;
    // Back (button or gesture) asks before leaving: leaving forfeits.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_l10n.appTitle),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: _l10n.gameLeave,
              icon: const Icon(Icons.exit_to_app),
              onPressed: _confirmLeave,
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shortest = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final boardSide = (shortest - 140).clamp(260.0, 520.0);

              final tokenGroups = <String, List<_TokenInfo>>{};
              final tokenGridById = <String, math.Point<int>>{};
              for (final token in _tokensById.values) {
                final player = _playersById[token.playerId];
                final pathColor = _pathColorForBackend(player?.color ?? '');
                final tokenIndex = tokenIndexById[token.id] ?? 0;
                final grid = _gridForToken(
                  token: token,
                  pathColor: pathColor,
                  tokenIndex: tokenIndex,
                );
                tokenGridById[token.id] = grid;
                final key = 'g:${grid.x}:${grid.y}';
                (tokenGroups[key] ??= []).add(token);
              }
              for (final group in tokenGroups.values) {
                group.sort((a, b) => a.id.compareTo(b.id));
              }

              final tileSize = boardSide / 15;
              final tokenVisualSize = (tileSize * 0.9).clamp(22.0, 48.0);
              final stackRadius = (tileSize * 0.22).clamp(
                3.0,
                tokenVisualSize * 0.25,
              );

              final tokenWidgets = <Widget>[];
              for (final group in tokenGroups.values) {
                for (int i = 0; i < group.length; i++) {
                  final token = group[i];
                  final player = _playersById[token.playerId];
                  final color = MajlisColors.seatColor(player?.color);

                  final isMine = token.playerId == me;
                  final canTap =
                      isMine &&
                      !_isAnimatingMove &&
                      !_isReconnecting &&
                      _canMoveToken(token);

                  final grid = tokenGridById[token.id];
                  if (grid == null) continue;

                  final baseCenter = LudoPath.gridToPixel(
                    x: grid.x,
                    y: grid.y,
                    boardSize: boardSide,
                  );
                  final center =
                      baseCenter + _spreadOffset(i, group.length, stackRadius);

                  tokenWidgets.add(
                    AnimatedPlayerToken(
                      center: center,
                      size: tokenVisualSize,
                      duration: _moveStepDuration,
                      child: PlayerToken(
                        color: color,
                        label: tokenLabels[token.id] ?? '',
                        enabled: isMine ? canTap : true,
                        flashing: _flashingTokenIds.contains(token.id),
                        onTap: canTap ? () => _moveToken(token.id) : null,
                      ),
                    ),
                  );
                }
              }

              return Center(
                child: SizedBox(
                  width: boardSide,
                  height: boardSide,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned.fill(child: BoardWidget()),
                      ...tokenWidgets,
                      for (int seat = 0; seat < playersInSeat.length; seat++)
                        if (playersInSeat[seat] != null)
                          _buildPlayerPanel(playersInSeat[seat]!, seat),
                      Positioned(
                        left: -10,
                        bottom: -10,
                        child: _buildStatusChip(),
                      ),
                      Positioned(
                        right: -10,
                        bottom: -10,
                        child: DiceWidget(
                          value: lastDice,
                          enabled: canRollDice,
                          rolling: _isRollingDice,
                          onTap: _rollDice,
                        ),
                      ),
                      if (_isAnimatingMove || _isReconnecting)
                        Positioned.fill(
                          child: AbsorbPointer(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              color: majlis.scrim.withValues(alpha: 0.18),
                              child: Center(
                                child: Text(
                                  _isReconnecting
                                      ? _l10n.gameReconnecting
                                      : _l10n.gameMoving,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: majlis.onSeat,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
