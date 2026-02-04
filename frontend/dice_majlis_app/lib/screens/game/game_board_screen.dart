import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/routes.dart';
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

  _TokenInfo copyWith({
    int? position,
    bool? isFinished,
  }) {
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
  final Map<String, int> _seatByPlayerId = {};
  final Map<String, _TokenInfo> _tokensById = {};

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

    final parsedRoomCode = (args is Map ? args['room_code'] : null)?.toString() ?? stored?.roomCode;
    final parsedPlayerId = (args is Map ? args['player_id'] : null)?.toString() ?? stored?.playerId;

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

    final delaySeconds = math.min(20, math.pow(2, _reconnectAttempts - 1).toInt());
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
      myPlayerId != null && currentTurnPlayerId != null && myPlayerId == currentTurnPlayerId;

  bool _canMoveToken(_TokenInfo token) {
    final dice = lastDice;
    if (!isMyTurn || dice == null) return false;
    if (token.isFinished) return false;

    if (token.position == -1) {
      return dice == 6;
    }

    return token.position + dice <= 100;
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

    final nextSeatByPlayerId = _computeSeatMap(nextPlayerOrder);

    setState(() {
      _playersById
        ..clear()
        ..addAll(nextPlayersById);
      _playerOrder
        ..clear()
        ..addAll(nextPlayerOrder);
      _seatByPlayerId
        ..clear()
        ..addAll(nextSeatByPlayerId);
      _tokensById
        ..clear()
        ..addAll(nextTokensById);
      currentTurnPlayerId = data['current_turn_player_id']?.toString();
      lastDice = (data['last_dice'] as num?)?.toInt();
      _reconnectAttempts = 0;
      _isReconnecting = false;
      _isRollingDice = false;
    });
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

    final nextSeatByPlayerId = _computeSeatMap(nextOrder);

    setState(() {
      _playersById.addAll(nextPlayersById);
      if (nextOrder.isNotEmpty) {
        _playerOrder
          ..clear()
          ..addAll(nextOrder);
        _seatByPlayerId
          ..clear()
          ..addAll(nextSeatByPlayerId);
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

    _animationQueue = _animationQueue.then((_) {
      return _animateTokenMove(
        tokenId: tokenId,
        from: from,
        to: to,
        dice: dice,
        killedTokenIds: killed,
      );
    });
  }

  Future<void> _animateTokenMove({
    required String tokenId,
    required int? from,
    required int to,
    required int? dice,
    required List<String> killedTokenIds,
  }) async {
    if (!mounted) return;

    final startToken = _tokensById[tokenId];
    if (startToken == null) return;

    final start = from ?? startToken.position;
    final steps = <int>[];

    if (start == -1) {
      steps.add(0);
    } else {
      for (int p = start + 1; p <= to; p++) {
        steps.add(p);
      }
    }

    setState(() {
      _isAnimatingMove = true;
    });

    // Movement time scales with dice value (more steps, slightly faster per step).
    final perStepMs = dice == null ? 140 : (180 - (dice * 15)).clamp(80, 160);
    final stepDelay = Duration(milliseconds: perStepMs);

    for (final p in steps) {
      if (!mounted) return;

      setState(() {
        final current = _tokensById[tokenId];
        if (current != null) {
          _tokensById[tokenId] = current.copyWith(position: p);
        }
      });

      await Future.delayed(stepDelay);
    }

    if (!mounted) return;

    if (killedTokenIds.isNotEmpty) {
      setState(() {
        for (final killedId in killedTokenIds) {
          final killedToken = _tokensById[killedId];
          if (killedToken != null) {
            _tokensById[killedId] = killedToken.copyWith(position: -1, isFinished: false);
            _flashingTokenIds.add(killedId);
          }
        }
      });

      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      setState(() {
        _flashingTokenIds.removeAll(killedTokenIds);
      });
    }

    if (!mounted) return;

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
      await ApiService.rollDice(roomCode: room, playerId: me);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRollingDice = false;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _moveToken(String tokenId) async {
    final room = roomCode;
    final me = myPlayerId;
    if (room == null || me == null) return;
    if (_isReconnecting || _isAnimatingMove) return;

    try {
      await ApiService.moveToken(roomCode: room, playerId: me, tokenId: tokenId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
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
      case 'orange':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Map<String, int> _computeSeatMap(List<String> playerOrder) {
    if (playerOrder.isEmpty) return {};

    final me = myPlayerId;
    if (me == null) {
      return {for (int i = 0; i < playerOrder.length; i++) playerOrder[i]: i};
    }

    final myIndex = playerOrder.indexOf(me);
    if (myIndex == -1) {
      return {for (int i = 0; i < playerOrder.length; i++) playerOrder[i]: i};
    }

    final rotated = <String>[
      ...playerOrder.skip(myIndex),
      ...playerOrder.take(myIndex),
    ];

    return {for (int i = 0; i < rotated.length; i++) rotated[i]: i};
  }

  int _seatForPlayerId(String playerId) => _seatByPlayerId[playerId] ?? 0;

  Offset _spreadOffset(int index, int count, double radius) {
    if (count <= 1) return Offset.zero;
    final angle = (2 * math.pi) * (index / count);
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  Offset _homeAnchorForSeat(int seat, Size size) {
    final margin = size.width * 0.18;
    return switch (seat % 4) {
      0 => Offset(size.width * 0.5, size.height - margin),
      1 => Offset(size.width - margin, size.height * 0.5),
      2 => Offset(size.width * 0.5, margin),
      _ => Offset(margin, size.height * 0.5),
    };
  }

  Offset _finishAnchorForSeat(int seat, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final pull = size.width * 0.12;
    return switch (seat % 4) {
      0 => center + Offset(0, pull),
      1 => center + Offset(pull, 0),
      2 => center + Offset(0, -pull),
      _ => center + Offset(-pull, 0),
    };
  }

  Offset _boardAnchorForPosition(int position, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final padding = size.width * 0.12;
    final radius = (size.width * 0.5) - padding;
    final angle = (-math.pi / 2) + (2 * math.pi) * (position / 100.0);
    return center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  Offset _tokenAnchor({
    required _TokenInfo token,
    required Size boardSize,
    required int stackIndex,
    required int stackCount,
  }) {
    final seat = _seatForPlayerId(token.playerId);

    if (token.position == -1) {
      return _homeAnchorForSeat(seat, boardSize) + _spreadOffset(stackIndex, stackCount, 16);
    }

    if (token.position >= 100) {
      return _finishAnchorForSeat(seat, boardSize) + _spreadOffset(stackIndex, stackCount, 14);
    }

    return _boardAnchorForPosition(token.position, boardSize) + _spreadOffset(stackIndex, stackCount, 10);
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
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
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
    for (final entry in tokensByPlayer.entries) {
      final tokens = entry.value;
      for (int i = 0; i < tokens.length; i++) {
        tokenLabels[tokens[i].id] = '${i + 1}';
      }
    }

    final playersInSeat = List<_PlayerInfo?>.filled(4, null);
    for (final id in _playerOrder) {
      final info = _playersById[id];
      final seat = _seatByPlayerId[id];
      if (info != null && seat != null && seat >= 0 && seat < 4) {
        playersInSeat[seat] = info;
      }
    }

    final canRollDice = currentTurnPlayerId != null &&
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
            final shortest = math.min(constraints.maxWidth, constraints.maxHeight);
            final boardSide = (shortest - 140).clamp(260.0, 520.0);
            final boardSize = Size(boardSide, boardSide);

            final tokenGroups = <String, List<_TokenInfo>>{};
            for (final token in _tokensById.values) {
              final key = token.position == -1
                  ? 'home:${token.playerId}'
                  : token.position >= 100
                      ? 'finish:${token.playerId}'
                      : 'pos:${token.position}';
              (tokenGroups[key] ??= []).add(token);
            }
            for (final group in tokenGroups.values) {
              group.sort((a, b) => a.id.compareTo(b.id));
            }

            const tokenVisualSize = 44.0;

            final tokenWidgets = <Widget>[];
            for (final group in tokenGroups.values) {
              for (int i = 0; i < group.length; i++) {
                final token = group[i];
                final player = _playersById[token.playerId];
                final color = player == null ? Colors.grey : _playerColor(player.color);

                final isMine = token.playerId == me;
                final canTap = isMine && !_isAnimatingMove && !_isReconnecting && _canMoveToken(token);

                final anchor = _tokenAnchor(
                  token: token,
                  boardSize: boardSize,
                  stackIndex: i,
                  stackCount: group.length,
                );

                tokenWidgets.add(
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeInOut,
                    left: anchor.dx - (tokenVisualSize / 2),
                    top: anchor.dy - (tokenVisualSize / 2),
                    child: SizedBox(
                      width: tokenVisualSize,
                      height: tokenVisualSize,
                      child: PlayerToken(
                        color: color,
                        label: tokenLabels[token.id] ?? '',
                        enabled: isMine ? canTap : true,
                        flashing: _flashingTokenIds.contains(token.id),
                        onTap: canTap ? () => _moveToken(token.id) : null,
                      ),
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
                      if (playersInSeat[seat] != null) _buildPlayerPanel(playersInSeat[seat]!, seat),
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
                                _isReconnecting ? 'Reconnecting...' : 'Moving...',
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
