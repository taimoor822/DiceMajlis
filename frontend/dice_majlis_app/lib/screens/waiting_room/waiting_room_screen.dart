import 'package:dice_majlis_app/app/routes.dart';
import 'package:dice_majlis_app/widgets/neon_button.dart';
import 'package:flutter/material.dart';

class WaitingRoomScreen extends StatelessWidget {
  const WaitingRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TEMP mock data (later from backend)
    final String roomCode = "AB12";
    final List<String> players = ["Player 1", "Player 2"];
    final bool isHost = true;

    return Scaffold(
      appBar: AppBar(title: const Text('Waiting Room')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room code
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Room Code: $roomCode",
                  style: const TextStyle(fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Room code copied')),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            const Text('Players', style: TextStyle(fontSize: 18)),

            const SizedBox(height: 12),

            // Player list
            Expanded(
              child: ListView.builder(
                itemCount: 4,
                itemBuilder: (context, index) {
                  if (index < players.length) {
                    final isFirst = index == 0;
                    return ListTile(
                      leading: Icon(
                        isFirst ? Icons.emoji_events : Icons.person,
                        color: isFirst ? Colors.amber : Colors.white,
                      ),
                      title: Text(players[index]),
                    );
                  } else {
                    return const ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text('Waiting for player...'),
                    );
                  }
                },
              ),
            ),

            if (isHost)
              SizedBox(
                width: double.infinity,
                child: NeonButton(
                  text: 'START GAME',
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.gameBoard);
                  },
                ),
              )
            else
              // ignore: dead_code
              const Center(
                child: Text('Waiting for host to start the game...'),
              ),
          ],
        ),
      ),
    );
  }
}
