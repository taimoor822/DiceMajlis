import 'dart:async';
import 'dart:convert';

import 'package:dice_majlis_app/app.dart';
import 'package:dice_majlis_app/core/auth/account.dart';
import 'package:dice_majlis_app/core/auth/auth_api.dart';
import 'package:dice_majlis_app/core/auth/social_sign_in.dart';
import 'package:dice_majlis_app/core/auth/token_store.dart';
import 'package:dice_majlis_app/core/network/api_exception.dart';
import 'package:dice_majlis_app/core/realtime/realtime_connection.dart';
import 'package:dice_majlis_app/core/realtime/realtime_message.dart';
import 'package:dice_majlis_app/core/realtime/realtime_providers.dart';
import 'package:dice_majlis_app/core/websocket/socket_providers.dart';
import 'package:dice_majlis_app/core/websocket/socket_service.dart';
import 'package:dice_majlis_app/core/entitlements/entitlements.dart';
import 'package:dice_majlis_app/features/achievements/data/achievements_repository.dart';
import 'package:dice_majlis_app/features/achievements/domain/achievements.dart';
import 'package:dice_majlis_app/features/cosmetics/data/items_repository.dart';
import 'package:dice_majlis_app/features/cosmetics/domain/inventory.dart';
import 'package:dice_majlis_app/features/stats/data/stats_repository.dart';
import 'package:dice_majlis_app/features/stats/domain/player_stats.dart';
import 'package:dice_majlis_app/features/games/data/game_catalog_repository.dart';
import 'package:dice_majlis_app/features/games/domain/game_catalog.dart';
import 'package:dice_majlis_app/features/multiplayer/data/room_repository.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_info.dart';
import 'package:dice_majlis_app/features/multiplayer/domain/room_session.dart';
import 'package:dice_majlis_app/features/profile/data/account_repository.dart';
import 'package:dice_majlis_app/features/profile/domain/profile_options.dart';
import 'package:dice_majlis_app/features/rewards/data/rewards_repository.dart';
import 'package:dice_majlis_app/features/rewards/domain/daily_reward.dart';
import 'package:dice_majlis_app/features/rewards/domain/reward_bundle.dart';
import 'package:dice_majlis_app/features/wallet/data/wallet_repository.dart';
import 'package:dice_majlis_app/features/wallet/domain/wallet_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Room API without a server. Records calls; [failWith] makes every call fail
/// with that server error code (e.g. `room_full`, `network_error`).
class FakeRoomRepository implements RoomRepository {
  FakeRoomRepository({
    this.failWith,
    this.options = const RoomOptions(
      playerCounts: [2, 3, 4],
      defaultPlayerCount: 4,
    ),
    this.joinStarted = false,
  });

  String? failWith;
  RoomOptions options;

  /// The game the last create-room call asked for.
  GameChoice? createdGame;

  /// Joining returns a room whose game has already started (rejoining).
  bool joinStarted;
  final calls = <String>[];

  void _maybeFail() {
    final code = failWith;
    if (code != null) throw ApiException(code);
  }

  RoomSession _session(String code, {required bool host, int? maxPlayers}) =>
      RoomSession(
        roomCode: code,
        playerId: host ? 'p-host' : 'p-guest',
        isHost: host,
        isStarted: !host && joinStarted,
        maxPlayers: maxPlayers,
        self: RoomPlayer(
          id: host ? 'p-host' : 'p-guest',
          name: host ? 'Guest 6789' : 'Guest 4321',
          color: host ? 'red' : 'blue',
          isHost: host,
        ),
      );

  @override
  Future<RoomOptions> roomOptions(GameChoice game) async {
    calls.add(game == const GameChoice() ? 'options' : 'options:$game');
    _maybeFail();
    return options;
  }

  @override
  Future<RoomSession> createRoom({
    required int maxPlayers,
    required GameChoice game,
  }) async {
    calls.add('create:$maxPlayers');
    createdGame = game;
    _maybeFail();
    return _session(
      'AB12',
      host: true,
      maxPlayers: maxPlayers,
    ).copyWith(gameType: game.gameType, variant: game.variant);
  }

  @override
  Future<RoomSession> joinRoom(String code) async {
    calls.add('join:$code');
    _maybeFail();
    return _session(code, host: false, maxPlayers: 4);
  }

  @override
  Future<void> startGame(String roomCode) async {
    calls.add('start:$roomCode');
    _maybeFail();
  }

  @override
  Future<RollResult> rollDice(String roomCode) async {
    calls.add('roll:$roomCode');
    _maybeFail();
    return const RollResult(dice: 6, movableTokenIds: []);
  }

  @override
  Future<void> moveToken(String roomCode, String tokenId) async {
    calls.add('move:$roomCode:$tokenId');
    _maybeFail();
  }

  @override
  Future<void> leaveRoom(String roomCode) async {
    calls.add('leave:$roomCode');
    _maybeFail();
  }

  /// What `invites()` returns.
  List<RoomInvite> pendingInvites = [];

  /// What `rematch()` returns.
  RematchAnswer rematchAnswer = const RematchAnswer();

  @override
  Future<void> setReady(String roomCode, {required bool ready}) async {
    calls.add('ready:$roomCode:$ready');
    _maybeFail();
  }

  @override
  Future<void> kickPlayer(String roomCode, String playerId) async {
    calls.add('kick:$roomCode:$playerId');
    _maybeFail();
  }

  @override
  Future<void> lockRoom(String roomCode, {required bool locked}) async {
    calls.add('lock:$roomCode:$locked');
    _maybeFail();
  }

  @override
  Future<void> transferHost(String roomCode, String playerId) async {
    calls.add('host:$roomCode:$playerId');
    _maybeFail();
  }

  @override
  Future<void> changeRules(
    String roomCode,
    Map<String, Object?> options,
  ) async {
    calls.add('rules:$roomCode:$options');
    _maybeFail();
  }

  @override
  Future<void> invitePlayer(String roomCode, int playerId) async {
    calls.add('invite:$roomCode:$playerId');
    _maybeFail();
  }

  @override
  Future<void> declineInvite(String roomCode) async {
    calls.add('decline:$roomCode');
    _maybeFail();
  }

  /// How many times Home loaded the invites (not in [calls]: Home loads
  /// them whenever it opens).
  int inviteLoads = 0;

  @override
  Future<List<RoomInvite>> invites() async {
    inviteLoads++;
    return pendingInvites;
  }

  @override
  Future<RematchAnswer> rematch(String roomCode, {required bool want}) async {
    calls.add('rematch:$roomCode:$want');
    _maybeFail();
    return rematchAnswer;
  }
}

/// The server's game catalog without a server: Ludo Classic unless a test
/// gives other games. [failWith] makes loading fail with that code.
class FakeGameCatalogRepository implements GameCatalogRepository {
  FakeGameCatalogRepository({List<CatalogGame>? games, this.failWith})
    : games = games ?? [ludoClassic];

  static const ludoClassic = CatalogGame(
    gameType: 'ludo',
    defaultVariant: 'classic',
    variants: [
      CatalogVariant(
        code: 'classic',
        minPlayers: 2,
        maxPlayers: 4,
        defaultPlayers: 4,
        ranked: true,
      ),
    ],
  );

  List<CatalogGame> games;
  String? failWith;
  int loads = 0;

  @override
  Future<List<CatalogGame>> catalog() async {
    loads++;
    final code = failWith;
    if (code != null) throw ApiException(code);
    return games;
  }
}

/// The account the fake server signs everyone in as.
const testAccount = Account(
  playerId: 123456789,
  displayName: 'Player 6789',
  isGuest: true,
  avatar: 'dhow',
  levelXp: 0,
  nextLevelXp: 100,
);

/// Sign-in API without a server. [failWith] makes calls fail with that code
/// (`network_error`, `session_revoked`, ...). Each answer has new tokens.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({this.account = testAccount, this.failWith, Duration? lifetime})
    : lifetime = lifetime ?? const Duration(minutes: 15);

  Account account;
  String? failWith;

  /// How long each access token lasts (zero: every request refreshes).
  Duration lifetime;
  final calls = <String>[];
  int _issued = 0;

  AuthTokens _tokens() {
    final code = failWith;
    if (code != null) throw ApiException(code);
    _issued++;
    return AuthTokens(
      access: 'access-$_issued',
      refresh: 'refresh-$_issued',
      accessExpiresIn: lifetime,
      account: account,
    );
  }

  @override
  Future<AuthTokens> signInAsGuest({
    required String deviceId,
    required String platform,
  }) async {
    calls.add('guest:$deviceId');
    return _tokens();
  }

  @override
  Future<AuthTokens> register({
    required String email,
    required String password,
    required String deviceId,
    required String platform,
  }) async {
    calls.add('register:$email');
    final tokens = _tokens();
    account = account.copyWith(email: email, isGuest: false);
    return AuthTokens(
      access: tokens.access,
      refresh: tokens.refresh,
      accessExpiresIn: tokens.accessExpiresIn,
      account: account,
    );
  }

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
    required String deviceId,
    required String platform,
  }) async {
    calls.add('login:$email:$password');
    return _tokens();
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    calls.add('reset:$email');
    final code = failWith;
    if (code != null) throw ApiException(code);
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    calls.add('confirm:$email:$code:$newPassword');
    final failure = failWith;
    if (failure != null) throw ApiException(failure);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    calls.add('refresh:$refreshToken');
    return _tokens();
  }

  @override
  Future<Account> me(String access) async => account;

  @override
  Future<void> signOut(String access) async => calls.add('signOut:$access');

  /// What `GET /api/auth/providers/` says is set up on the server.
  Map<String, dynamic> serverProviders = {'google': false, 'apple': false};

  @override
  Future<Map<String, dynamic>> providers() async => serverProviders;

  @override
  Future<AuthTokens> socialSignIn({
    required String provider,
    required String idToken,
    String? nonce,
    required String deviceId,
    required String platform,
  }) async {
    calls.add('social:$provider:$idToken${nonce == null ? '' : ':$nonce'}');
    final tokens = _tokens();
    account = account.copyWith(isGuest: false, linked: [provider]);
    return AuthTokens(
      access: tokens.access,
      refresh: tokens.refresh,
      accessExpiresIn: tokens.accessExpiresIn,
      account: account,
    );
  }
}

/// Google / Apple on the phone without the plugins: [usable] providers work,
/// returning `<provider>-token` ([cancel] = the player closes the sheet).
class FakeSocialSignIn implements SocialSignIn {
  FakeSocialSignIn({Set<SocialProvider>? usable})
    : usable = usable ?? {SocialProvider.google, SocialProvider.apple};

  Set<SocialProvider> usable;
  bool cancel = false;
  final asked = <SocialProvider>[];

  @override
  Future<bool> canUse(SocialProvider provider) async =>
      usable.contains(provider);

  @override
  Future<SocialCredential> credential(SocialProvider provider) async {
    asked.add(provider);
    if (cancel) throw const SocialSignInCancelled();
    return SocialCredential(
      idToken: '${provider.key}-token',
      nonce: provider == SocialProvider.apple ? 'apple-nonce' : null,
    );
  }
}

/// Profile and account changes without a server: applies them to the
/// signed-in account and records them. [failWith] fails every call (an
/// `ApiException` with that code and [fieldErrors]).
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({this.account = testAccount});

  Account account;
  String? failWith;
  Map<String, List<String>> fieldErrors = const {};
  final calls = <String>[];

  ProfileOptions options = const ProfileOptions(
    avatars: ['dice', 'dhow', 'moon'],
    languages: ['en', 'ar', 'ur', 'pa'],
    maxLanguages: 2,
    nameMinLength: 2,
    nameMaxLength: 20,
  );

  void _maybeFail() {
    final code = failWith;
    if (code != null) throw ApiException(code, fieldErrors: fieldErrors);
  }

  @override
  Future<ProfileOptions> profileOptions() async {
    calls.add('options');
    return options;
  }

  @override
  Future<Account> updateProfile({
    String? displayName,
    String? avatar,
    String? country,
    List<String>? languages,
  }) async {
    calls.add(
      'update:${[if (displayName != null) 'name=$displayName', if (avatar != null) 'avatar=$avatar', if (country != null) 'country=$country', if (languages != null) 'languages=${languages.join(',')}'].join(' ')}',
    );
    _maybeFail();
    return account = account.copyWith(
      displayName: displayName?.trim() ?? account.displayName,
      avatar: avatar ?? account.avatar,
      country: country == null
          ? account.country
          : (country.isEmpty ? null : country),
      languages: languages ?? account.languages,
    );
  }

  @override
  Future<Account> saveAccount({
    required String email,
    required String password,
  }) async {
    calls.add('save:$email');
    _maybeFail();
    return account = account.copyWith(email: email, isGuest: false);
  }

  @override
  Future<Account> linkSocial(
    SocialProvider provider,
    SocialCredential credential,
  ) async {
    calls.add('link:${provider.key}:${credential.idToken}');
    _maybeFail();
    return account = account.copyWith(
      isGuest: false,
      linked: [...account.linked, provider.key]..sort(),
    );
  }

  @override
  Future<Account> unlinkSocial(SocialProvider provider) async {
    calls.add('unlink:${provider.key}');
    _maybeFail();
    return account = account.copyWith(
      linked: [
        for (final key in account.linked)
          if (key != provider.key) key,
      ],
    );
  }
}

/// The wallet without a server: [balances] and a list of [entries] (newest
/// first), served [pageSize] at a time.
/// Items without a server: the starter set, and whatever a test adds. Equip
/// checks ownership and slot like the server does.
class FakeItemsRepository implements ItemsRepository {
  FakeItemsRepository({List<OwnedItem>? items})
    : items = items ?? [...starterItems];

  static const starterItems = [
    OwnedItem(
      code: 'dice_ivory',
      type: 'cosmetic',
      slot: 'dice',
      name: 'Ivory',
      rarity: 'common',
      asset: 'dice_ivory',
      starter: true,
    ),
    OwnedItem(
      code: 'dice_desert_gold',
      type: 'cosmetic',
      slot: 'dice',
      name: 'Desert Gold',
      rarity: 'rare',
      asset: 'dice_desert_gold',
      starter: true,
    ),
    OwnedItem(
      code: 'board_majlis',
      type: 'cosmetic',
      slot: 'board',
      name: 'Majlis',
      rarity: 'common',
      asset: 'board_majlis',
      starter: true,
    ),
    OwnedItem(
      code: 'board_oasis',
      type: 'cosmetic',
      slot: 'board',
      name: 'Oasis',
      rarity: 'rare',
      asset: 'board_oasis',
      starter: true,
    ),
    OwnedItem(
      code: 'frame_brass',
      type: 'cosmetic',
      slot: 'frame',
      name: 'Brass Ring',
      rarity: 'common',
      asset: 'frame_brass',
      starter: true,
    ),
  ];

  List<OwnedItem> items;
  final equipped = <String, String?>{
    'dice': 'dice_ivory',
    'board': 'board_majlis',
    'frame': null,
  };
  final calls = <String>[];
  String? failWith;

  Inventory get _inventory => Inventory(
    items: items,
    equipped: Map.of(equipped),
    cosmetics: {
      for (final entry in equipped.entries)
        entry.key: entry.value == null
            ? null
            : items.firstWhere((item) => item.code == entry.value).asset,
    },
  );

  @override
  Future<Inventory> inventory() async {
    calls.add('inventory');
    final code = failWith;
    if (code != null) throw ApiException(code);
    return _inventory;
  }

  @override
  Future<Inventory> equip(String slot, String? item) async {
    calls.add('equip:$slot:$item');
    final code = failWith;
    if (code != null) throw ApiException(code);
    if (item != null) {
      final owned = items.where((i) => i.code == item).firstOrNull;
      if (owned == null) throw const ApiException('not_owned');
      if (owned.slot != slot) throw const ApiException('wrong_slot');
    }
    // Nothing chosen: the slot's first starter (a frame may stay empty).
    equipped[slot] =
        item ??
        (slot == 'frame'
            ? null
            : items.firstWhere((i) => i.slot == slot).code);
    return _inventory;
  }
}

/// Entitlements without a server: none until a test sets [entitlements].
class FakeEntitlementsRepository implements EntitlementsRepository {
  FakeEntitlementsRepository({this.entitlements = const Entitlements()});

  Entitlements entitlements;
  int loads = 0;

  @override
  Future<Entitlements> mine() async {
    loads++;
    return entitlements;
  }
}

/// Achievements without a server: none until a test sets [overview].
class FakeAchievementsRepository implements AchievementsRepository {
  FakeAchievementsRepository({this.overview = const AchievementsOverview()});

  AchievementsOverview overview;
  String? failWith;
  int loads = 0;

  @override
  Future<AchievementsOverview> myAchievements() async {
    loads++;
    final code = failWith;
    if (code != null) throw ApiException(code);
    return overview;
  }
}

/// Statistics without a server: none until a test sets [stats].
class FakeStatsRepository implements StatsRepository {
  FakeStatsRepository({this.stats = const StatsOverview()});

  StatsOverview stats;
  String? failWith;
  int loads = 0;

  @override
  Future<StatsOverview> myStats() async {
    loads++;
    final code = failWith;
    if (code != null) throw ApiException(code);
    return stats;
  }
}

class FakeWalletRepository implements WalletRepository {
  FakeWalletRepository({
    this.balance = const Balances(gold: 1250, diamond: 5),
    List<WalletEntry>? entries,
    this.pageSize = 30,
  }) : entries = entries ?? [];

  Balances balance;
  List<WalletEntry> entries;
  int pageSize;
  String? failWith;
  final calls = <String>[];

  @override
  Future<Balances> balances() async {
    calls.add('balances');
    final code = failWith;
    if (code != null) throw ApiException(code);
    return balance;
  }

  @override
  Future<WalletPage> history({String? before}) async {
    calls.add('history:${before ?? 'first'}');
    final code = failWith;
    if (code != null) throw ApiException(code);
    final start = before == null
        ? 0
        : entries.indexWhere((e) => e.id == before) + 1;
    final page = entries.skip(start).take(pageSize).toList();
    final more = start + page.length < entries.length;
    return WalletPage(entries: page, next: more ? page.last.id : null);
  }
}

/// The 7-day cycle the fake server uses.
const testDailyDays = [
  DailyRewardDay(day: 1, gold: 100),
  DailyRewardDay(day: 2, gold: 150),
  DailyRewardDay(day: 3, gold: 200),
  DailyRewardDay(day: 4, gold: 250),
  DailyRewardDay(day: 5, gold: 300),
  DailyRewardDay(day: 6, gold: 400),
  DailyRewardDay(day: 7, gold: 500, diamond: 5),
];

/// Daily rewards without a server. Claiming adds today's reward to
/// [wallet]'s balance, like the real server.
class FakeRewardsRepository implements RewardsRepository {
  FakeRewardsRepository({
    this.day = 1,
    this.claimedToday = false,
    FakeWalletRepository? wallet,
  }) : wallet = wallet ?? FakeWalletRepository();

  int day;
  bool claimedToday;
  final FakeWalletRepository wallet;
  String? failWith;
  final calls = <String>[];

  /// Rewards already given, newest first.
  List<RewardHistoryEntry> given = [];

  @override
  Future<RewardHistoryPage> history({String? before}) async {
    calls.add('history:${before ?? 'first'}');
    final code = failWith;
    if (code != null) throw ApiException(code);
    return RewardHistoryPage(entries: given);
  }

  DailyRewardStatus get _status => DailyRewardStatus(
    day: day,
    claimedToday: claimedToday,
    days: testDailyDays,
    secondsUntilReset: 5 * 3600 + 120,
  );

  @override
  Future<DailyRewardStatus> dailyStatus() async {
    calls.add('status');
    return _status;
  }

  @override
  Future<DailyClaimResult> claimDaily() async {
    calls.add('claim');
    final code = failWith;
    if (code != null) throw ApiException(code);
    if (claimedToday) throw const ApiException('already_claimed');
    claimedToday = true;
    final got = testDailyDays[day - 1];
    wallet.balance = Balances(
      gold: wallet.balance.gold + got.gold,
      diamond: wallet.balance.diamond + got.diamond,
    );
    return DailyClaimResult(
      claimed: got,
      balances: wallet.balance,
      status: _status,
    );
  }
}

/// Token storage in memory. Starts with [refreshToken] (null = signed out).
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore({this.refreshToken});

  String? refreshToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveRefreshToken(String token) async => refreshToken = token;

  @override
  Future<void> clearRefreshToken() async => refreshToken = null;

  @override
  Future<String> deviceId() async => 'test-device-0001';
}

/// A socket the test drives by hand: [emit] plays a server message.
class FakeSocketService extends SocketService {
  // sync: a message reaches the screen as soon as the test emits it.
  final _controller = StreamController<dynamic>.broadcast(sync: true);
  String? connectedRoom;
  String? connectedRoomId;
  bool disconnected = false;

  @override
  void connect(String roomCode, {String? roomId}) {
    connectedRoom = roomCode;
    connectedRoomId = roomId;
  }

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void disconnect() => disconnected = true;

  void emit(Map<String, dynamic> message) =>
      _controller.add(jsonEncode(message));
}

/// Every socket the app opened, newest last.
class FakeSockets {
  final opened = <FakeSocketService>[];
  FakeSocketService get last => opened.last;

  FakeSocketService create() {
    final socket = FakeSocketService();
    opened.add(socket);
    return socket;
  }
}

/// One fake `/ws/v1/` socket (see [FakeRealtimeServer]).
class FakeRealtimeConnection implements RealtimeConnection {
  FakeRealtimeConnection(this._server);

  final FakeRealtimeServer _server;
  final _incoming = StreamController<String>();

  /// Everything the app sent, decoded.
  final sent = <Map<String, dynamic>>[];

  /// Channels this socket subscribed to (and didn't leave).
  final channels = <String>{};

  bool signedIn = false;
  bool closed = false;

  @override
  int? closeCode;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String text) {
    final message = Map<String, dynamic>.from(jsonDecode(text) as Map);
    sent.add(message);
    _server._answer(this, message);
  }

  @override
  Future<void> close() async => serverClose(1000);

  /// The server ends this socket with [code] (e.g. 4401 bad token).
  void serverClose(int code) {
    if (closed) return;
    closed = true;
    closeCode = code;
    _incoming.close();
  }

  /// The server sends [message] to this socket.
  void push(Map<String, dynamic> message) {
    if (!closed) _incoming.add(jsonEncode(message));
  }

  /// Requests of [type] the app sent on this socket.
  List<Map<String, dynamic>> sentOfType(String type) =>
      [for (final m in sent) if (m['type'] == type) m];
}

/// A fake `/ws/v1/` server: signs in any token (unless [refuseTokens]),
/// answers pings and subscriptions, and lets the test [push] channel events.
class FakeRealtimeServer {
  final connections = <FakeRealtimeConnection>[];

  /// The server can't be reached (connecting throws).
  bool reachable = true;

  /// Tokens the server refuses (closes 4401), e.g. an expired one.
  final refuseTokens = <String>{};

  /// Leave pings unanswered (a dead connection).
  bool answerPings = true;

  /// Events a new subscriber of a channel gets right after the ack.
  final initialEvents = <String, List<Map<String, dynamic>>>{};

  /// For a subscribe with `since` (coming back): the events to send instead
  /// of [initialEvents], or null for those. Every subscribe's data is kept in
  /// [subscribes].
  List<Map<String, dynamic>>? Function(String channel, int since)? catchUp;
  final subscribes = <Map<String, dynamic>>[];

  /// Answers to other requests (`roll_dice`, `request_state`, …): return the
  /// ack's data, or throw a [RealtimeException] to refuse with its code.
  final handlers =
      <String, Map<String, dynamic> Function(Map<String, dynamic> data)>{};

  /// The access tokens the app signed in with, in order.
  final tokens = <String>[];

  FakeRealtimeConnection get last => connections.last;

  /// Every connection attempt, reachable or not.
  int attempts = 0;

  Future<RealtimeConnection> connect(Uri uri) async {
    attempts++;
    if (!reachable) throw StateError('server unreachable');
    final connection = FakeRealtimeConnection(this);
    connections.add(connection);
    return connection;
  }

  /// An event on [channel], to every open socket subscribed to it.
  void push(
    String channel,
    String type,
    Map<String, dynamic> data, {
    int? version,
  }) {
    for (final connection in connections) {
      if (!connection.closed && connection.channels.contains(channel)) {
        connection.push(_event(channel, type, data, version));
      }
    }
  }

  static Map<String, dynamic> _event(
    String channel,
    String type,
    Map<String, dynamic> data,
    int? version,
  ) => {
    'v': 1,
    'type': type,
    'channel': channel,
    'data': data,
    if (version != null) 'version': version,
  };

  void _answer(FakeRealtimeConnection connection, Map<String, dynamic> m) {
    final reqId = m['req_id'];
    final data = Map<String, dynamic>.from((m['data'] ?? const {}) as Map);
    Map<String, dynamic> ack([Map<String, dynamic> body = const {}]) => {
      'v': 1,
      'type': 'ack',
      'req_id': reqId,
      'data': body,
    };
    switch (m['type']) {
      case 'auth':
        final token = data['access_token'] as String;
        tokens.add(token);
        if (refuseTokens.contains(token)) {
          connection.push({
            'v': 1,
            'type': 'error',
            'req_id': reqId,
            'code': 'token_expired',
            'message': 'Access token expired',
          });
          connection.serverClose(4401);
          return;
        }
        connection.signedIn = true;
        connection.push(ack({'player_id': 123456789, 'heartbeat_seconds': 20}));
      case 'ping':
        if (answerPings) {
          connection.push({'v': 1, 'type': 'pong', 'req_id': reqId});
        }
      case 'subscribe':
        final channel = data['channel'] as String;
        subscribes.add(data);
        connection.channels.add(channel);
        connection.push(ack({'channel': channel}));
        final since = data['since'];
        final missed = since is int ? catchUp?.call(channel, since) : null;
        for (final event in missed ?? initialEvents[channel] ?? const []) {
          connection.push(event);
        }
      case 'unsubscribe':
        connection.channels.remove(data['channel']);
        connection.push(ack({'channel': data['channel']}));
      default:
        final handler = handlers[m['type']];
        if (handler == null) {
          connection.push({
            'v': 1,
            'type': 'error',
            'req_id': reqId,
            'code': 'unknown_type',
            'message': 'Unknown request',
          });
          return;
        }
        try {
          connection.push(ack(handler(data)));
        } on RealtimeException catch (error) {
          connection.push({
            'v': 1,
            'type': 'error',
            'req_id': reqId,
            'code': error.code,
            'message': error.message ?? error.code,
          });
        }
    }
  }
}

/// Provider overrides that swap the network for fakes. Without [auth] and
/// [tokens] the player has a saved sign-in, so the app opens signed in.
List<Override> fakeNetwork({
  required FakeRoomRepository repository,
  required FakeSockets sockets,
  FakeAuthApi? auth,
  MemoryTokenStore? tokens,
  FakeAccountRepository? accounts,
  FakeWalletRepository? wallet,
  FakeRewardsRepository? rewards,
  FakeGameCatalogRepository? catalog,
  FakeRealtimeServer? realtime,
  FakeSocialSignIn? social,
  FakeItemsRepository? items,
  FakeStatsRepository? stats,
  FakeAchievementsRepository? achievements,
  FakeEntitlementsRepository? entitlements,
}) => [
  ...fakeEconomy(wallet: wallet, rewards: rewards),
  itemsRepositoryProvider.overrideWithValue(items ?? FakeItemsRepository()),
  statsRepositoryProvider.overrideWithValue(stats ?? FakeStatsRepository()),
  achievementsRepositoryProvider.overrideWithValue(
    achievements ?? FakeAchievementsRepository(),
  ),
  entitlementsRepositoryProvider.overrideWithValue(
    entitlements ?? FakeEntitlementsRepository(),
  ),
  socialSignInProvider.overrideWithValue(social ?? FakeSocialSignIn()),
  realtimeConnectorProvider.overrideWithValue(
    (realtime ?? FakeRealtimeServer()).connect,
  ),
  roomRepositoryProvider.overrideWithValue(repository),
  gameCatalogRepositoryProvider.overrideWithValue(
    catalog ?? FakeGameCatalogRepository(),
  ),
  accountRepositoryProvider.overrideWithValue(
    accounts ?? FakeAccountRepository(),
  ),
  socketServiceFactoryProvider.overrideWithValue(sockets.create),
  authApiProvider.overrideWithValue(auth ?? FakeAuthApi()),
  tokenStoreProvider.overrideWithValue(
    tokens ?? MemoryTokenStore(refreshToken: 'saved-refresh'),
  ),
];

/// Wallet and daily reward fakes (Home shows both).
List<Override> fakeEconomy({
  FakeWalletRepository? wallet,
  FakeRewardsRepository? rewards,
}) {
  final walletFake = wallet ?? rewards?.wallet ?? FakeWalletRepository();
  return [
    walletRepositoryProvider.overrideWithValue(walletFake),
    rewardsRepositoryProvider.overrideWithValue(
      rewards ?? FakeRewardsRepository(wallet: walletFake),
    ),
  ];
}

/// The whole app with fakes in place of the network. [overrides] adds more
/// (e.g. settings storage).
Widget testApp({
  required FakeRoomRepository repository,
  required FakeSockets sockets,
  FakeAuthApi? auth,
  MemoryTokenStore? tokens,
  FakeAccountRepository? accounts,
  FakeWalletRepository? wallet,
  FakeRewardsRepository? rewards,
  FakeGameCatalogRepository? catalog,
  FakeRealtimeServer? realtime,
  FakeSocialSignIn? social,
  FakeItemsRepository? items,
  FakeStatsRepository? stats,
  FakeAchievementsRepository? achievements,
  FakeEntitlementsRepository? entitlements,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    ...fakeNetwork(
      repository: repository,
      sockets: sockets,
      auth: auth,
      tokens: tokens,
      accounts: accounts,
      wallet: wallet,
      rewards: rewards,
      catalog: catalog,
      realtime: realtime,
      social: social,
      items: items,
      stats: stats,
      achievements: achievements,
      entitlements: entitlements,
    ),
    ...overrides,
  ],
  child: const DiceMajlisApp(),
);
