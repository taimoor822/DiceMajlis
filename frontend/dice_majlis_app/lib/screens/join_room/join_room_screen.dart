import 'package:dice_majlis_app/widgets/neon_button.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../app/routes.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController roomCodeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Room')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: roomCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Room Code',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: NeonButton(
                text: 'JOIN',
                onPressed: () async {
                  try {
                    final result = await ApiService.joinRoom(
                      code: roomCodeController.text.trim(),
                      name: 'Player',
                      color: 'blue',
                    );

                    if (!context.mounted) return;

                    Navigator.pushNamed(
                      context,
                      AppRoutes.waitingRoom,
                      arguments: result,
                    );
                  } catch (e) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to join room')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
