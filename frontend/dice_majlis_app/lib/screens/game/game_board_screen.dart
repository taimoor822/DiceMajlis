import 'dart:convert';
import 'package:flutter/material.dart';

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

class _GameBoardScreenState extends State<GameBoardScreen> {
  late SocketService socket;
  bool _initialized = false;

  late String roomCode;
  late String myPlayerId;

  String currentTurnPlayerId = '';
  int? lastDice;

  /// tokenId -> position
  Map<String, int> tokenPositions = {};

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

    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    roomCode = args['room_code'];
    myPlayerId = args['player_id'];
    currentTurnPlayerId = args['current_turn'];

    socket.connect(roomCode);

    socket.stream.listen((event) {
      if (!mounted) return;
      final data = jsonDecode(event);

      switch (data['type']) {
        case 'dice_rolled':
          setState(() {
            lastDice = data['dice'];
          });
          break;

        case 'token_moved':
          setState(() {
            tokenPositions[data['token_id']] = data['to'];

            for (final killedId in data['killed']) {
              tokenPositions[killedId] = -1; // back to home
            }

            lastDice = null;
          });
          break;

        case 'turn_changed':
          setState(() {
            currentTurnPlayerId = data['player_id'];
            lastDice = null;
          });
          break;

        case 'game_finished':
          _showWinner(data['winner_id']);
          break;
      }
    });
  }

  @override
  void dispose() {
    socket.disconnect();
    super.dispose();
  }

  bool get isMyTurn => myPlayerId == currentTurnPlayerId;

  void _showWinner(String winnerId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Game Over'),
        content: Text(winnerId == myPlayerId ? 'You Win! 🎉' : 'You Lost 😢'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

              // 🔴 Example token (real logic later)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: PlayerToken(
                    color: Colors.red,
                    label: 'P1',
                    enabled: isMyTurn && lastDice != null,
                    onTap: () async {
                      await ApiService.moveToken(
                        code: roomCode,
                        playerId: myPlayerId,
                        tokenId: 'TOKEN_ID_HERE',
                      );
                    },
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
                        enabled: isMyTurn && lastDice == null,
                        onTap: () async {
                          await ApiService.rollDice(
                            roomCode: roomCode,
                            playerId: myPlayerId,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    isMyTurn ? 'Your Turn' : 'Opponent Turn',
                    style: TextStyle(
                      color: isMyTurn ? Colors.greenAccent : Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
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
