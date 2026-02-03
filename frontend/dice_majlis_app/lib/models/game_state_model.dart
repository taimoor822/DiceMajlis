class GameState {
  String currentTurnPlayerId;
  int? lastDice;

  Map<String, List<TokenState>> tokensByPlayer;

  GameState({
    required this.currentTurnPlayerId,
    this.lastDice,
    required this.tokensByPlayer,
  });
}

class TokenState {
  String id;
  int position; // -1 = base, 0+ path, 100 = finished

  TokenState({required this.id, required this.position});
}
