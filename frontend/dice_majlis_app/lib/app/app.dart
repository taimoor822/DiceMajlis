import 'package:flutter/material.dart';
import 'routes.dart';
import 'theme.dart';

class DiceMajlisApp extends StatelessWidget {
  const DiceMajlisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dice Majlis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
    );
  }
}
