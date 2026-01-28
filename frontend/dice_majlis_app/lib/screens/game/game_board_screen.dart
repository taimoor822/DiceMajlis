import 'package:flutter/material.dart';

import '../../widgets/glow_container.dart';
import 'widgets/board_widget.dart';
import 'widgets/dice_widget.dart';
import 'widgets/player_token.dart';

class GameBoardScreen extends StatelessWidget {
  const GameBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dice Majlis'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              // ================= CENTER BOARD =================
              Center(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: const BoardWidget(),
                ),
              ),

              // ================= PLAYER TOKENS =================

              // Bottom (Player 1)
              const Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: PlayerToken(
                    color: Colors.red,
                    label: 'P1',
                  ),
                ),
              ),

              // Top (Player 2)
              const Positioned(
                top: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: PlayerToken(
                    color: Colors.blue,
                    label: 'P2',
                  ),
                ),
              ),

              // Left (Player 3)
              const Positioned(
                left: 100,
                top: 0,
                bottom: 0,
                child: Center(
                  child: PlayerToken(
                    color: Colors.green,
                    label: 'P3',
                  ),
                ),
              ),

              // Right (Player 4)
              const Positioned(
                right: 100,
                top: 0,
                bottom: 0,
                child: Center(
                  child: PlayerToken(
                    color: Colors.orange,
                    label: 'P4',
                  ),
                ),
              ),

              // ================= DICE =================
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12, right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Tap to roll',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(height: 8),
                      DiceWidget(),
                    ],
                  ),
                ),
              ),

              // ================= TURN INDICATOR =================
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'Current Turn: Player 1',
                    style: TextStyle(
                      color: Colors.redAccent,
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
