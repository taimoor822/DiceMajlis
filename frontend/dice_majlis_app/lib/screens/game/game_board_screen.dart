import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';

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

  const _PlayerInfo({
    required this.id,
    required this.name,
    required this.color,
    required this.isHost,
  });

  factory _PlayerInfo.fromJson(Map<String, dynamic> json) {
    return _PlayerInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      isHost: json['is_host'] == true,
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

  final Map<String, _PlayerInfo> _playersById = {};
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
    if (route == null || route.settings.arguments == null) {
      _redirectHome();
      return;
    }

    final args = route.settings.arguments;
    if (args is! Map) {
      _redirectHome();
      return;
    }

    final parsedRoomCode = args['room_code']?.toString();
    final parsedPlayerId = args['player_id']?.toString();

    if (parsedRoomCode == null || parsedPlayerId == null) {
      _redirectHome();
      return;
    }

    roomCode = parsedRoomCode;
    myPlayerId = parsedPlayerId;

    socket.connect(roomCode!);
    _socketConnected = true;

    _socketSubscription = socket.stream.listen(
      _handleSocketEvent,
      onError: (error) {
        debugPrint('Socket error: $error');
      },
    );
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    if (_socketConnected) {
      socket.disconnect();
    }
    super.dispose();
  }

  bool get isMyTurn =>
      myPlayerId != null && currentTurnPlayerId != null && myPlayerId == currentTurnPlayerId;

  void _redirectHome() {
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
          });
          break;

        case 'token_moved':
          _applyTokenMoved(data);
          break;

        case 'turn_changed':
          setState(() {
            currentTurnPlayerId = data['player_id']?.toString();
            lastDice = null;
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
    if (players is List) {
      for (final p in players) {
        if (p is Map) {
          final info = _PlayerInfo.fromJson(Map<String, dynamic>.from(p));
          if (info.id.isNotEmpty) {
            nextPlayersById[info.id] = info;
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
      _playersById
        ..clear()
        ..addAll(nextPlayersById);
      _tokensById
        ..clear()
        ..addAll(nextTokensById);
      currentTurnPlayerId = data['current_turn_player_id']?.toString();
      lastDice = (data['last_dice'] as num?)?.toInt();
    });
  }

  void _applyPlayersUpdated(Map<String, dynamic> data) {
    final players = data['players'];
    if (players is! List) return;

    setState(() {
      for (final p in players) {
        if (p is Map) {
          final info = _PlayerInfo.fromJson(Map<String, dynamic>.from(p));
          if (info.id.isNotEmpty) {
            _playersById[info.id] = info;
          }
        }
      }
    });
  }

  void _applyTokenMoved(Map<String, dynamic> data) {
    final tokenId = data['token_id']?.toString();
    final to = (data['to'] as num?)?.toInt();
    if (tokenId == null || to == null) return;

    final killed = data['killed'];

    setState(() {
      final existing = _tokensById[tokenId];
      if (existing != null) {
        _tokensById[tokenId] = existing.copyWith(position: to);
      }

      if (killed is List) {
        for (final k in killed) {
          final killedId = k?.toString();
          if (killedId == null) continue;
          final killedToken = _tokensById[killedId];
          if (killedToken != null) {
            _tokensById[killedId] = killedToken.copyWith(position: -1, isFinished: false);
          }
        }
      }

      lastDice = null;
    });
  }

  Future<void> _rollDice() async {
    final room = roomCode;
    final me = myPlayerId;
    if (room == null || me == null) return;

    try {
      await ApiService.rollDice(roomCode: room, playerId: me);
    } catch (e) {
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

    try {
      await ApiService.moveToken(code: room, playerId: me, tokenId: tokenId);
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

  void _showWinner(String winnerId) {
    final me = myPlayerId;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Dice Majlis'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: const BoardWidget(),
                ),
              ),

              Align(
                alignment: Alignment.topLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTurnPlayerId == null
                            ? 'Syncing game state...'
                            : isMyTurn
                                ? 'Your Turn'
                                : 'Opponent Turn',
                        style: TextStyle(
                          color: isMyTurn ? Colors.greenAccent : Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_playersById.isNotEmpty && tokensByPlayer.isNotEmpty)
                        ..._playersById.values.map((p) {
                          final playerTokens = tokensByPlayer[p.id] ?? const <_TokenInfo>[];
                          if (playerTokens.isEmpty) return const SizedBox.shrink();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _playerColor(p.color),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (int i = 0; i < playerTokens.length; i++)
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          PlayerToken(
                                            color: _playerColor(p.color),
                                            label: 'T${i + 1}',
                                            enabled: p.id == me && isMyTurn && lastDice != null,
                                            onTap: () => _moveToken(playerTokens[i].id),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            playerTokens[i].position.toString(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        })
                      else
                        const Text(
                          'Waiting for server state...',
                          style: TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ),

              // 🎲 Dice
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12, right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Tap to roll',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      DiceWidget(
                        value: lastDice,
                        enabled: currentTurnPlayerId != null && isMyTurn && lastDice == null,
                        onTap: _rollDice,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
