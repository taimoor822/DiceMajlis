import 'package:flutter/material.dart';

import '../screens/splash/splash_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/create_room/create_room_screen.dart';
import '../screens/join_room/join_room_screen.dart';
import '../screens/waiting_room/waiting_room_screen.dart';
import '../screens/game/game_board_screen.dart';



class AppRoutes {
  static const splash = '/';
  static const home = '/home';
  static const createRoom = '/create-room';
  static const joinRoom = '/join-room';
  static const waitingRoom = '/waiting-room';
  static const gameBoard = '/game-board';


  static final routes = <String, WidgetBuilder>{
    splash: (_) => const SplashScreen(),
    home: (_) => const HomeScreen(),
    createRoom: (_) => const CreateRoomScreen(),
    joinRoom: (_) => const JoinRoomScreen(),
    waitingRoom: (_) => const WaitingRoomScreen(),
    gameBoard: (_) => const GameBoardScreen(),

  };
}
