import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/neon_button.dart';

class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  late final SocketService socket;

  String? roomCode;
  String? playerId;
  bool isHost = false;

  bool _initialized = false;

  List<Map<String, dynamic>> players = [];

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

    // 🔒 SAFETY: arguments may be null on web refresh
    if (route == null || route.settings.arguments == null) {
      _redirectHome();
      return;
    }

    final args = route.settings.arguments;
    if (args is! Map<String, dynamic>) {
      _redirectHome();
      return;
    }

    final room = args['room'];
    final player = args['player'];

    if (room == null || player == null) {
      _redirectHome();
      return;
    }

    roomCode = room['code']?.toString();
    playerId = player['id']?.toString();
    isHost = player['is_host'] == true;

    if (roomCode == null || playerId == null) {
      _redirectHome();
      return;
    }

    // Add current player immediately
    players = [Map<String, dynamic>.from(player)];

    // 🔌 Connect WebSocket
    socket.connect(roomCode!);

    socket.stream.listen((event) {
      if (!mounted) return;

      try {
        final data = jsonDecode(event);

        switch (data['type']) {
          case 'players_updated':
            setState(() {
              players = List<Map<String, dynamic>>.from(data['players']);
            });
            break;

          case 'game_started':
            Navigator.pushReplacementNamed(
              context,
              AppRoutes.gameBoard,
              arguments: {
                'room_code': roomCode,
                'player_id': playerId,
              },
            );
            break;
        }
      } catch (e) {
        debugPrint('Socket parse error: $e');
      }
    });
  }

  void _redirectHome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    });
  }

  @override
  void dispose() {
    socket.disconnect();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    // While redirecting or loading
    if (roomCode == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Waiting Room'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= ROOM CODE =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Room Code: $roomCode',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: roomCode!));
                    if (!context.mounted) return;
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

            Expanded(
              child: ListView.builder(
                itemCount: 4,
                itemBuilder: (context, index) {
                  if (index < players.length) {
                    final p = players[index];
                    return ListTile(
                      leading: Icon(
                        Icons.person,
                        color: _playerColor(p['color']),
                      ),
                      title: Text(p['name']),
                      trailing: p['is_host'] ? const Text('Host') : null,
                    );
                  }

                  return const ListTile(
                    leading: Icon(Icons.person_outline),
                    title: Text('Waiting...'),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            if (isHost)
              SizedBox(
                width: double.infinity,
                child: NeonButton(
                  text: 'START GAME',
                  onPressed: () async {
                    await ApiService.startGame(
                      code: roomCode!,
                      playerId: playerId!,
                    );
                  },
                ),
              )
            else
              const Center(
                child: Text(
                  'Waiting for host to start the game...',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
