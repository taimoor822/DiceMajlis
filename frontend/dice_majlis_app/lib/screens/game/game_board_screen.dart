import 'package:flutter/material.dart';

// Custom widgets
import 'widgets/board_widget.dart';
import 'widgets/dice_widget.dart';
import 'widgets/player_token.dart';

class GameBoardScreen extends StatelessWidget {
  const GameBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ---------- TOP BAR ----------
      appBar: AppBar(
        title: const Text('Dice Majlis'),
        centerTitle: true,
      ),

      // ---------- MAIN BODY ----------
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),

          // Stack lets us place items on top of each other
          child: Stack(
            children: [
              // =================================================
              // 1️⃣ GAME BOARD (CENTER)
              // =================================================
              Center(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: const BoardWidget(),
                ),
              ),

              // =================================================
              // 2️⃣ PLAYER TOKENS (AROUND BOARD)
              // =================================================

              // Player 1 – Bottom
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

              // Player 2 – Top
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

              // Player 3 – Left
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

              // Player 4 – Right
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

              // =================================================
              // 3️⃣ DICE (BOTTOM RIGHT)
              // =================================================
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

              // =================================================
              // 4️⃣ TURN INDICATOR (BOTTOM LEFT)
              // =================================================
              const Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 20),
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
