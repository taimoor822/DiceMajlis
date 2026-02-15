import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../game/ludo_path.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../services/session_storage.dart';

// Widgets
import 'widgets/board_widget.dart';
import 'widgets/dice_widget.dart';
import 'widgets/player_token.dart';

class GameBoardScreen extends StatefulWidget {
  const GameBoardScreen({super.key});

  @override
  State<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _PlayerInfo {
  final String id;
  final String name;
  final String color;
  final bool isHost;
  final bool isBot;

  const _PlayerInfo({
    required this.id,
    required this.name,
    required this.color,
    required this.isHost,
    required this.isBot,
  });

  factory _PlayerInfo.fromJson(Map<String, dynamic> json) {
    return _PlayerInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      isHost: json['is_host'] == true,
      isBot: json['is_bot'] == true,
    );
  }
}

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
      isFinished: isFinished ?? this.isFinished || nextPosition == 100,
    );
  }

  factory _TokenInfo.fromJson(Map<String, dynamic> json) {
    final position = (json['position'] as num?)?.toInt() ?? -1;
    return _TokenInfo(
      id: json['id']?.toString() ?? '',
      playerId: json['player_id']?.toString() ?? '',
      position: position,
      isFinished: json['is_finished'] == true || position == 100,
    );
  }
}

class _GameBoardScreenState extends State<GameBoardScreen> {
  late SocketService socket;
  bool _initialized = false;
  bool _socketConnected = false;
  StreamSubscription<dynamic>? _socketSubscription;

  String? roomCode;
  String? myPlayerId;

  String? currentTurnPlayerId;
  int? lastDice;

  bool _isRollingDice = false;
  bool _isAnimatingMove = false;
  bool _isReconnecting = false;
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
    socket = SocketService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final route = ModalRoute.of(context);
    final args = route?.settings.arguments;

    final stored = SessionStorage.load();

    final parsedRoomCode =
        (args is Map ? args['room_code'] : null)?.toString() ??
        stored?.roomCode;
    final parsedPlayerId =
        (args is Map ? args['player_id'] : null)?.toString() ??
        stored?.playerId;

    if (parsedRoomCode == null || parsedPlayerId == null) {
      _redirectHome();
      return;
    }

    roomCode = parsedRoomCode;
    myPlayerId = parsedPlayerId;
    SessionStorage.save(roomCode: parsedRoomCode, playerId: parsedPlayerId);

    _connectSocket();
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

    socket = SocketService();
    socket.connect(room);
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

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _reconnectTimer?.cancel();
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
    if (token.isFinished || token.position == 100) return false;

    if (token.position < 0) {
      return dice == 6;
    }

    final lastIndex = LudoPath.redPath.length - 1;
    if (token.position >= lastIndex) return false;
    return token.position + dice <= lastIndex;
  }

  void _redirectHome() {
    SessionStorage.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
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
            _isRollingDice = false;
          });
          break;

        case 'game_finished':
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
      _reconnectAttempts = 0;
      _isReconnecting = false;
      _isRollingDice = false;
      _isAnimatingMove = false;
      _moveStepDuration = const Duration(milliseconds: 140);
    });

    _animationQueue = Future.value();
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
    if (to == 100) {
      toUi = lastIndex;
    } else if (to < 0) {
      toUi = -1;
    } else {
      toUi = to.clamp(0, lastIndex);
    }

    final startRaw = from ?? startToken.position;
    int startUi;
    if (startRaw == 100) {
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

    if (to == 100) {
      setState(() {
        final current = _tokensById[tokenId];
        if (current != null) {
          _tokensById[tokenId] = current.copyWith(
            position: 100,
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
      _isAnimatingMove = false;
    });
  }

  Future<void> _rollDice() async {
    final room = roomCode;
    final me = myPlayerId;
    if (room == null || me == null) return;
    if (_isReconnecting || _isAnimatingMove || _isRollingDice) return;

    setState(() {
      _isRollingDice = true;
    });

    try {
      final rolled = await ApiService.rollDice(roomCode: room, playerId: me);
      if (mounted && lastDice == null) {
        setState(() {
          lastDice = rolled;
          _isRollingDice = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRollingDice = false;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _moveToken(String tokenId) async {
    final room = roomCode;
    final me = myPlayerId;
    if (room == null || me == null) return;
    if (_isReconnecting || _isAnimatingMove) return;

    try {
      await ApiService.moveToken(
        roomCode: room,
        playerId: me,
        tokenId: tokenId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Color _playerColor(String color) {
    switch (color.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.amber;
      case 'orange':
        return Colors.orange;
      default:
        return Colors.grey;
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
    if (token.isFinished || token.position == 100) return pathLength - 1;
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
    final color = _playerColor(player.color);

    final title = [
      player.name,
      if (player.isBot) 'AI',
      if (isMe) 'You',
    ].join(' • ');

    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isTurn ? 0.35 : 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTurn ? color : Colors.white.withValues(alpha: 0.12),
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
    final text = currentTurnPlayerId == null
        ? 'Syncing...'
        : isMyTurn
        ? 'Your Turn'
        : 'Opponent Turn';

    final color = currentTurnPlayerId == null
        ? Colors.white70
        : isMyTurn
        ? Colors.greenAccent
        : Colors.redAccent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showWinner(String winnerId) {
    final me = myPlayerId;
    SessionStorage.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Game Over'),
        content: Text(me != null && winnerId == me ? 'You Win!' : 'You Lost'),
      ),
    );
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

    return Scaffold(
      appBar: AppBar(title: const Text('Dice Majlis'), centerTitle: true),
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
                final color = player == null
                    ? Colors.grey
                    : _playerColor(player.color);

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
                            color: Colors.black.withValues(alpha: 0.18),
                            child: Center(
                              child: Text(
                                _isReconnecting
                                    ? 'Reconnecting...'
                                    : 'Moving...',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
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
    );
  }
}
