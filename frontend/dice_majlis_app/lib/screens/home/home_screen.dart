import 'package:flutter/material.dart';
import '../../widgets/neon_button.dart';


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🎲 Dice Majlis',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00FF9C),
                ),
              ),
              const SizedBox(height: 50),

              SizedBox(
                width: double.infinity,
                child: NeonButton(
                  text: 'CREATE ROOM',
                  onPressed: () {
                    Navigator.pushNamed(context, '/create-room');
                  },
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: NeonButton(
                  text: 'JOIN ROOM',
                  onPressed: () {
                    Navigator.pushNamed(context, '/join-room');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
