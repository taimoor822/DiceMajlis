import 'package:flutter/material.dart';
import '../../widgets/neon_button.dart';
import '../../services/api_service.dart';
import '../../app/routes.dart';


class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  int selectedPlayers = 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Room')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Max Players',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [2, 3, 4].map((count) {
                return ChoiceChip(
                  label: Text('$count'),
                  selected: selectedPlayers == count,
                  onSelected: (_) {
                    setState(() {
                      selectedPlayers = count;
                    });
                  },
                );
              }).toList(),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: NeonButton(
                text: 'CREATE',
                onPressed: () async {
  try {
    final result = await ApiService.createRoom(
      name: 'Player 1',
      color: 'red',
      maxPlayers: selectedPlayers,
    );

    Navigator.pushNamed(
      context,
      AppRoutes.waitingRoom,
      arguments: result,
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to create room')),
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
