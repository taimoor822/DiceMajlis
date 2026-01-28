import 'package:flutter/material.dart';
import '../../app/routes.dart';
import '../../widgets/neon_button.dart';

class WaitingRoomScreen extends StatelessWidget {
  const WaitingRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ SAFELY read arguments from Navigator
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final room = args?['room'];
    final player = args?['player'];

    final String roomCode = room?['code'] ?? '----';
    final bool isHost = player?['is_host'] ?? false;

    // 🔹 TEMP players list (WebSockets later)
    final List<String> players = [
      player?['name'] ?? 'You',
      'Waiting...',
      'Waiting...',
      'Waiting...',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiting Room'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room Code
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Room Code: $roomCode',
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

            const Text(
              'Players',
              style: TextStyle(fontSize: 18),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: ListView.builder(
                itemCount: 4,
                itemBuilder: (context, index) {
                  final name = players[index];
                  final isCurrentPlayer = index == 0;

                  return ListTile(
                    leading: Icon(
                      isCurrentPlayer ? Icons.person : Icons.person_outline,
                      color: isCurrentPlayer
                          ? Theme.of(context).primaryColor
                          : Colors.white,
                    ),
                    title: Text(name),
                  );
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
              const Center(
                child: Text('Waiting for host to start the game...'),
              ),
          ],
        ),
      ),
    );
  }
}
