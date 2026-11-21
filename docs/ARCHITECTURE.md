# Dice Majlis — Technical Foundation

> Status: living document. Last updated 2026-11-21.
> Covers the 10 foundation items from the master build prompt, adapted to the code
> that already exists in this repository. Profiles, Majlis rooms and the gift economy
> are designed in [SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md); store, VIP, Royal levels and
> premium items in [ROYAL_VIP_ECONOMY.md](ROYAL_VIP_ECONOMY.md); the multi-game platform,
> competition, events and social feed in [PLATFORM.md](PLATFORM.md); the build order in
> [planning.md](planning.md).

**Contents**

1. [Technology stack](#1-technology-stack)
2. [System architecture](#2-system-architecture)
3. [Flutter folder structure](#3-flutter-folder-structure)
4. [Backend folder structure](#4-backend-folder-structure)
5. [Database architecture](#5-database-architecture)
6. [Game engine architecture](#6-game-engine-architecture)
7. [WebSocket architecture](#7-websocket-architecture)
8. [Authentication architecture](#8-authentication-architecture)
9. [Development environment](#9-development-environment)
10. [Phase-1 implementation plan](#10-phase-1-implementation-plan)

---

## Where we are today

What already works (Feb 2026 code):

- Create/join a private room with a 4-letter code, waiting room, host starts the game
- Server rolls the dice and enforces whose turn it is; one roll per move
- Bots that play their own turns
- A refreshed client gets the full game state over the socket
- Flutter screens: splash, home, create room, join room, waiting room, board

Bugs found while reviewing, and where each one is handled:

| Bug | Where | Effect | Status |
|---|---|---|---|
| Captures compare each player's *relative* progress | `game/utils.py` `kill_enemy_tokens` | Tokens get captured from a different square; tokens on the same square don't | ✅ 1.1 |
| Server finishes at 100, app's board path has 57 cells and blocks moves past 56 | `game/utils.py`, `game_board_screen.dart` | Human players can never bring a token home; only bots can win | ✅ 1.1 |
| Safe squares are `{0,10,…,90}` | `game/utils.py` | Don't match the stars/start squares on the board | ✅ 1.1 |
| Dice uses `random.randint` | `game/views.py` | Not cryptographically secure | ✅ 1.1 |
| Red path includes `(6,14)` then jumps diagonally into the home column | `ludo_path.dart` | Wrong animation at the end of the lap | ✅ 1.1 |
| No row locking on roll/move | `game/views.py` | Two fast requests can both pass the "already rolled?" check | ✅ 1.1 (row lock + version check) |
| Two copies of the rules (`game_logic.py` unused, `utils.py` used) | `game/` | Easy to fix one and not the other | ✅ 1.1 (both removed) |
| API/WS URLs hard-coded to `127.0.0.1` / `10.0.2.2` | `api_service.dart`, `socket_service.dart` | A real phone can't reach the server | ✅ 1.3 (`--dart-define=API_BASE_URL`) |
| No ASGI server or Postgres driver in `requirements.txt` | `backend/requirements.txt` | WebSockets need Daphne/Uvicorn, and `DB_ENGINE=postgres` needs `psycopg`, both installed by hand | ✅ 1.3 |
| Create Room always sends `red`, Join Room always sends `blue` | `create_room_screen.dart`, `join_room_screen.dart` | 3rd/4th players share a colour and a board path | ✅ 1.1 (server reassigns clashing colours to free seats) |
| `DATABASE_URL=sqlite:////abs/path` loses its leading `/` | `core/settings.py` | Absolute SQLite paths fail to open | ✅ 1.3 |
| Server trusts any `player_id` sent with start/roll/move; the whole room sees everyone's id | `game/views.py` | Anyone calling the API directly can play for another player | ✅ review fixes (seat secret), then 1.6 (seats belong to accounts, see below) |
| `create-room` accepts any `max_players` (0, 1, 5, `"abc"`) | `game/views.py` | Starting such a room crashes with a 500 | ✅ review fixes (validated 2–4, from the engine) |
| Join checks "room full" without a lock | `game/views.py` | Two people can take the last seat at once | ✅ review fixes (row lock) |
| Room codes from `random` | `game/views.py` | Predictable codes | ✅ review fixes (`secrets`) |
| Board guesses "needs a 6" before the server's movable list arrives | `game_board_screen.dart` | Wrong taps if the rule changes | ✅ review fixes (server list in roll response + snapshot) |
| Dice number drawn in the same navy as the dice | `dice_widget.dart` | The rolled number is invisible | ✅ review fixes |
| Colours and English text inline in the board widgets | `features/ludo/presentation/` | Breaks dark/light themes and translation | ✅ review fixes (`MajlisColors`, `app_en.arb`) |

---

## 1. Technology stack

### Decision: keep Django + Channels (don't switch to NestJS)

The prompt prefers NestJS but asks to evaluate alternatives. For this project,
right now, Django + Channels is the stronger choice:

| | Django + Channels | NestJS + Socket.IO |
|---|---|---|
| Existing code | Rooms, dice, turns, bots, reconnect already working | Full rewrite (weeks, no visible gain) |
| Fit for **turn-based** Ludo | Good — ~1 action per player every few seconds; the limit is open connections + Redis, not the framework | Good |
| Admin panel (prompt §32) | Built in (Django admin + groups/permissions) | Build or buy |
| Auth, ORM, migrations | Built in | Assemble (Passport, TypeORM/Prisma, …) |
| Languages to learn/maintain | Python + Dart | TypeScript + Dart (+ Python already written) |
| Escape hatch | Engine is framework-free (`ludo_engine/`); only the socket gateway would change | — |

"Django is slow for heavy real-time gaming" is true for fast action games (60
updates/second), not for dice games. We will **prove** capacity with load tests
(§36 of the prompt: 100 → 1,000 games, 10,000 connections) before claiming it.

**Revisit only if** a load test at target size shows the WebSocket layer is CPU-bound
and adding instances doesn't fix it. Then replace just the gateway.

### Full stack

| Layer | Choice | Why |
|---|---|---|
| App | Flutter (Android, iOS) | Already chosen |
| State | Riverpod (`flutter_riverpod`, codegen optional) | Testable, no BuildContext needed |
| Navigation | GoRouter | Redirects for auth (splash → login/home) |
| Models | Freezed + json_serializable | Immutable typed models, `copyWith`, unions for socket events |
| HTTP | Dio + interceptor (auth refresh) | Already in use |
| Realtime client | `web_socket_channel` + our own small protocol (§7) | Channels speaks plain WebSockets; our envelope gives acks/ids/versions without a second protocol like Socket.IO |
| Secure storage | `flutter_secure_storage` | Keychain/Keystore for refresh tokens |
| i18n | `flutter_localizations` + `gen-l10n` (ARB files: en, ar, ur) | RTL support for Arabic/Urdu |
| Backend | Python 3.12+, Django 6, DRF | Already in use |
| Realtime server | Django Channels 4 + `channels_redis` | Already in use |
| ASGI server | Daphne (dev: `runserver`), Uvicorn workers in prod | Missing today |
| Auth tokens | `djangorestframework-simplejwt` (+ token blacklist) | Access/refresh, rotation, logout-all |
| Database | PostgreSQL 16 | Transactions, JSONB, indexes |
| Cache / live state | Redis 7 | Channel layer, live game state, timers, presence, queues, leaderboards |
| Background jobs | Turn-timer worker (management command) now; Celery later | Timers must survive restarts |
| Push | Firebase Cloud Messaging (only push, Phase 4+) | Firebase used selectively, not as the backend |
| Errors | Sentry (Flutter + Django) | Crash + error tracking |
| Dev/infra | Docker Compose (Postgres + Redis); containers on a VM for staging | No Kubernetes until load requires it |
| CI | GitHub Actions: backend tests, `flutter analyze`, `flutter test` | |

---

## 2. System architecture

A **modular monolith**: one Django codebase, split into apps with clear boundaries.
Apps can become separate services later if metrics demand it — not before.

```
           Flutter app (Android / iOS)
             │ HTTPS (REST)      │ WSS (one socket per app session)
             ▼                   ▼
        ┌──────────────── Load balancer / NGINX (TLS) ───────────────┐
        │                                                            │
   ASGI instances (N, stateless) ── Django + DRF + Channels ──────────┤
        │  accounts · profiles · rooms · gameplay · matchmaking       │
        │  ranking · chat · social · wallet · tournaments · events    │
        │                    │                                        │
        │            ludo_engine (pure Python rules)                  │
        └───────┬──────────────────────┬──────────────────────────────┘
                │                      │
          PostgreSQL              Redis
          (source of truth)       (live game state, events window,
                                   timers, presence, queues,
                                   leaderboards, channel layer)
                ▲                      ▲
                └── Workers: turn timer · Celery jobs (rewards, tournaments, cleanup)
```

### One dice roll, end to end (server-authoritative)

```
1. Client  → {"type":"roll_dice","req_id":…,"data":{"game_id","expected_version":12}}
2. Consumer: authenticated? rate limit ok? req_id seen before? (then repeat the old ack)
3. Load state  game:{id}:state  from Redis
4. value = SecureDice().roll()                  # server RNG, never the client
5. transition = ludo_engine.roll(state, user_id, value)   # rules check + new state
6. Save only if stored version is still 12 (Lua script / WATCH) → else "stale_version"
7. Append action to the Postgres action log; push events to game:{id}:events
8. Broadcast events (dice_result, turn_ended, …) to the game group, version 13
9. Ack the sender; reset the turn timer
```

If Redis loses a game, it is rebuilt from Postgres with `ludo_engine.replay(initial, actions)`.
That only works because the engine is deterministic (§6).

### Turn timer ✅ (step 1.2, `game/timers.py`)

Each running game stores `Game.turn_deadline`, written **in the same transaction as the
game state**, so the clock and the state can never disagree. A new turn gets a fresh 30 s;
rolling doesn't reset it. A sweep runs every second, finds overdue turns and calls
`ludo_engine.timeout(..., expected_turn=turn_number)`: the server rolls, the bot logic
moves, and 3 missed turns in a row forfeit the player. A player who acted just before
the deadline already has a newer `turn_number`, so the stale timer is rejected. An
overdue **bot** just plays (its thread died; no penalty).

Where the sweep runs: inside every ASGI server process (`core/asgi.py`, on by default),
or as its own process with `GAME_TIMER_IN_PROCESS=false` + `python manage.py
run_turn_timers`. Several sweeps at once are safe. The app gets `seconds_left` (not a
timestamp, so a wrong phone clock doesn't matter) in `turn_changed` and on reconnect.

*Why the database and not a Redis sorted set (the original plan):* one source of truth
and one transaction, works on SQLite in development, and an indexed query per second is
cheap at this scale. Move to Redis when live games reach the tens of thousands.

### Scaling path

| Users | Setup |
|---|---|
| ≤ 1k | 1 VM: 2 ASGI processes, Postgres, Redis (Docker Compose) |
| 10k | Managed Postgres + Redis; 2–4 ASGI containers behind a load balancer |
| 100k | Separate WebSocket instances from REST instances; Redis for channel layer separate from cache; read replicas |
| 1M+ | Redis Cluster; shard live games by `game_id`; split hot apps (gameplay, chat) into services if metrics say so |

Rules that make this possible from day one: stateless API instances, all shared live
state in Redis, Postgres as the durable source of truth, indexes on every lookup,
pagination everywhere, assets on a CDN, background work in queues.

---

## 3. Flutter folder structure

Target (feature-first, each feature with `data / domain / presentation`):

```
lib/
├── main.dart                 # bootstrap: env, ProviderScope, runApp
├── app.dart                  # MaterialApp.router, themes, locale
├── core/
│   ├── config/               # Env (API/WS base URL via --dart-define), feature flags
│   ├── constants/
│   ├── errors/               # Failure types, error mapping from API/socket codes
│   ├── network/              # Dio client, auth interceptor, refresh lock
│   ├── websocket/            # socket client, envelope, reconnect/backoff, sync
│   ├── storage/              # secure storage, prefs
│   ├── theme/                # Majlis tokens (colors, type, spacing), dark + light
│   ├── routing/              # GoRouter + auth redirect
│   ├── l10n/                 # ARB files: en, ar, ur
│   ├── utils/
│   └── extensions/
├── shared/
│   ├── widgets/              # MajlisButton, GoldCard, LanternGlow, CoinBadge …
│   ├── components/
│   ├── animations/
│   └── models/
└── features/
    ├── splash/  authentication/  home/  profile/
    ├── ludo/                 # board, tokens, dice UI + Dart engine (offline)
    ├── multiplayer/  matchmaking/
    ├── leaderboard/  leagues/  tournaments/
    ├── chat/  messaging/  friends/
    ├── wallet/  events/  notifications/  settings/
    └── <feature>/
        ├── data/             # DTOs, remote/local data sources, repository impl
        ├── domain/           # entities, repository interfaces, (use cases only when they add logic)
        └── presentation/     # pages, widgets, Riverpod controllers
```

### What steps 1.4 and 1.5 built ✅

```
lib/
├── main.dart                     ProviderScope + runApp
├── app.dart                      MaterialApp.router: themes, router, translations
├── core/
│   ├── config/app_config.dart    server address (--dart-define=API_BASE_URL)
│   ├── network/api_service.dart  REST calls (Dio)
│   ├── websocket/                socket_service.dart + socket_providers.dart (swappable in tests)
│   ├── storage/                  session storage (browser storage on web, memory on phones),
│   │                             preferences.dart (device settings, shared_preferences)
│   ├── theme/                    majlis_palette (raw colours), majlis_colors (ThemeExtension,
│   │                             `context.majlis`), app_theme (dark + light), theme_mode_controller
│   ├── routing/                  app_routes (paths), app_router (GoRouter: tab shell + roomGuard)
│   └── l10n/                     app_en.arb → generated/ (flutter gen-l10n)
├── shared/widgets/               MajlisBackground, MajlisButton, MajlisCard, MajlisWordmark, GlowContainer,
│                                 ComingSoonPage + SoonBadge (honest placeholders), PlayerAvatar
└── features/
    ├── splash/presentation/      restores the sign-in, then the room / Home / Welcome
    ├── auth/presentation/        welcome, email (sign in / create), forgotten password
    ├── navigation/presentation/  main_shell.dart (bottom bar), tab_placeholders.dart
    ├── home/presentation/        Home lobby (Battle tab): play, profile card, shortcuts
    ├── profile/                  account_repository (profile, save account), profile screen,
    │                             save-account screen
    ├── wallet/                   wallet_repository + balancesProvider, balance chips (Home),
    │                             wallet screen (balances + history)
    ├── rewards/                  rewards_repository + dailyRewardProvider, daily reward card
    ├── games/                    1.10 game registry: GameModule per game_type (names, icon,
    │                             online board, offline route), server catalog, GameRouteScreen
    ├── hub/presentation/         Game Hub: online games from the catalog, play on this phone,
    │                             modes coming soon
    ├── local_play/               offline games (1.9): setup (who plays each colour),
    │                             LocalGameController (dice, AI turns, token walks), game screen
    ├── settings/presentation/    account (save, sign out), theme (saved on the device)
    ├── multiplayer/
    │   ├── data/room_repository.dart        typed room API (+ provider)
    │   ├── domain/room_session.dart         Freezed RoomSession / RoomPlayer
    │   ├── domain/room_session_controller.dart  current room (Riverpod Notifier)
    │   └── presentation/                    create, join, waiting room
    └── ludo/
        ├── domain/                ludo_path.dart, turn_clock.dart,
        │                          engine/ (the Dart rules engine, 1.9)
        └── presentation/          game_board_screen.dart (online) + widgets/
                                   (LudoBoardView: board + tokens, used by offline games)
```

- **Routes (1.5):** a `StatefulShellRoute` gives the bottom bar **Events · Game Hub ·
  Battle · Chat · Social**; each tab keeps its own history. Battle, in the centre, is the
  Home lobby where the app opens. `/events`, `/hub` (+ `/hub/create-room`,
  `/hub/join-room`), `/home` (+ `/home/profile`, `/home/wallet`, `/home/settings`,
  `/home/settings/save-account`), `/chat`, `/social`. Signed out: `/welcome`,
  `/welcome/email`, `/welcome/forgot`.
  Rooms and games are full screen above the bar: `/room/:code`, `/game/:code`.
  Back on another tab returns to the lobby; back there leaves the app.
  `roomGuard` sends room and game links without a matching session to Home
  (a stale link or a phone that restarted).
- **Unbuilt sections** (Events, Chat, Social, Shop, Rankings, ...) show
  `ComingSoonPage` / a "Soon" badge, never made-up content. Each is replaced by its
  real screen in its phase.
- **State:** Riverpod. Screens get the API through `roomRepositoryProvider` and sockets
  through `socketServiceFactoryProvider`, so widget tests swap in fakes
  (`test/helpers/fakes.dart`) and never touch the network.
- **Generated code is committed** (`*.freezed.dart`, `*.g.dart`, `l10n/generated/`).
  After changing a Freezed model or `app_en.arb`, run
  `dart run build_runner build --delete-conflicting-outputs` and `flutter gen-l10n`;
  CI fails if they are out of date.
- The board's strings and colours moved to l10n and theme tokens in the review fixes.
  Arabic and Urdu ARB files come with the language settings (Phase 2).
- Deleted: the old neon theme, `NeonButton`, `LoadingIndicator`, the unused win screen,
  and the empty `models/`, `providers/`, `utils/` files.

Rules: no colours or user-facing strings inside widgets (theme tokens + l10n only);
no business logic in widgets; every socket/API payload is a typed Freezed model.

---

## 4. Backend folder structure

```
backend/
├── requirements.txt           # → requirements/{base,dev,prod}.txt in step 1.3
└── core/                      # Django project root (manage.py)
    ├── core/                  # settings, asgi.py, urls.py  (→ settings/{base,dev,prod}.py)
    ├── ludo_engine/           # ✅ BUILT — pure Python rules, no Django imports
    │   ├── board.py  rules.py  state.py  engine.py  events.py
    │   ├── dice.py   bot.py    errors.py
    │   ├── vectors.py         # 1.9 shared test vectors for the app's Dart engine
    │   └── tests/             # 75 tests incl. 300 simulated full games
    ├── game_platform/         # ✅ 1.10 — pure: the GameEngine contract, the registry
    │                          # (game_type → engine), Ludo's adapter (variant Classic)
    ├── game/                  # rooms + REST + WS; services.py = the only code that changes game
    │                          # state, for any registered game; tables/ = per-game extras
    │                          # (Ludo: Token rows + today's socket messages)
    ├── accounts/              # 1.6 users + Player ID, device sessions, JWT, guest sign-in;
    │                          #     1.7 email sign-up/in, save guest account, reset code
    │                          #     (Google/Apple 1.15, phone later)
    ├── profiles/              # 1.7 display name, built-in avatar, country, languages, XP → level
    │                          #     (frames and stats summary later)
    ├── wallet/                # 1.8 gold + diamonds: accounts, append-only ledger, admin
    │                          #     adjustments, audit (purchases P9)
    ├── rewards/               # 1.8 grant() engine, reward-day, daily login reward
    │                          #     (admin bundles, items, missions, pass later)
    │
    │  planned apps (each added in the phase that needs it)
    ├── realtime/              # P2 socket envelope, auth, rate limits, idempotency
    ├── gameplay/              # P2 Redis game store, action log, turn-timer worker
    ├── matchmaking/           # P2 queues, rating windows
    ├── ranking/               # P3 ratings, leagues, seasons, leaderboards
    ├── chat/  social/         # P4 rooms, messages, friends, blocks, reports, presence
    ├── missions/  achievements/  pass/   # later: progress engine on top of rewards/
    ├── tournaments/           # P6 brackets, registration, payouts
    ├── notifications/         # push (FCM), in-app inbox
    └── moderation/            # reports, mutes, bans, audit log
```

Inside every app:

```
<app>/
├── models.py        # tables
├── services.py      # write logic (the only place that changes data)
├── selectors.py     # read queries
├── api/             # DRF views + serializers (thin)
├── consumers.py     # socket handlers (thin: validate → call services)
├── admin.py
└── tests/
```

---

## 5. Database architecture

> Phase numbers in this section predate the social expansion. Social, wallet and gift
> tables are now specified in [SOCIAL_MAJLIS.md §3](SOCIAL_MAJLIS.md#3-backend-apps-and-tables).

**PostgreSQL is the source of truth. Redis holds only things that can be rebuilt or
expire.** All primary keys are UUIDs; every table has `created_at`; money-like data is
append-only.

### PostgreSQL (by phase)

| Phase | Table | Key columns / constraints |
|---|---|---|
| 1 | `accounts_user` | id (UUID), player_id (9 digits, unique), username (unique, case-insensitive), email (unique, nullable), phone (unique, nullable, later), is_guest, is_active, last_login |
| 1 | `accounts_device_session` | user, device_id, platform, refresh_hash, previous_refresh_hash, rotated_at, refresh_expires_at, last_seen_at, revoked_at, revoked_reason — powers "log out other devices" |
| 1 | `profiles_profile` | user (1:1, also the key), display_name, avatar (built-in picture key), country (ISO code or ""), languages (list), xp — the level is worked out from xp, not stored |
| 1 | `accounts_password_reset_code` | user, code_hash (keyed), created_at, expires_at, attempts, used_at |
| 1→2 | `gameplay_game` | id, room, mode (2p/4p/team), ranked, status, rules (JSONB), initial_state (JSONB), final_state (JSONB), winner, started_at, ended_at |
| 2 | `gameplay_game_player` | game, user, seat, place, rating_before/after — unique(game, seat), unique(game, user) |
| ✅ 1.1 | `game_gameaction` (→ `gameplay_game_action`) | game, version, action (JSONB), created_at — unique(game, version). **The audit log for disputes and replays** |
| 2 | `rooms_room` | id, code (unique), host, mode, visibility, max_players, status |
| 3 | `ranking_rating` | user, season, rating, rd (Glicko), wins, losses, games, streak, league |
| 3 | `ranking_season`, `ranking_league` | |
| 4 | `chat_room`, `chat_message` | message: room, sender, type (text/emoji/system), body, created_at — index(room, created_at) |
| 4 | `chat_conversation`, `chat_read_marker` | 1:1 chats, read status |
| 4 | `social_friendship`, `social_friend_request`, `social_block`, `moderation_report` | unique pairs, both directions checked |
| 1.8 | `wallet_walletaccount` | user, currency (`gold` / `diamond`), balance (cached, `>= 0` check), last_sequence; unique (user, currency) |
| 1.8 | `wallet_wallettransaction` | account, **sequence** (1, 2, 3 … per account), amount (+/−, never 0), balance_before, balance_after (checks: `after = before + amount`, `after >= 0`), type, source, reference_type/id, **idempotency_key (unique per account)**, metadata, created_at |
| 1.8 | `wallet_walletadjustment` | admin grant/revoke: user, currency, amount, reason, created_by, the ledger entry it posted |
| 1.8 | `rewards_rewardclaim` | user, kind (`daily_login` …), reward_day, streak_day, bundle, **idempotency_key (unique)** |
| 5 | `missions_*`, `achievements_*`, `pass_*` | |
| 6 | `tournaments_tournament`, `_participant`, `_match` | |
| all | `audit_log` | actor, action, target, data, ip — admin and sensitive actions |

**Wallet rule (built in 1.8):** balances only change through `wallet.services.post()`,
inside a DB transaction with `SELECT … FOR UPDATE` on the account, writing one
numbered, immutable ledger row (saving or deleting an existing row raises; the admin
is read only). The same `idempotency_key` twice returns the first entry — no double
credit. Mistakes are fixed with `wallet.services.reverse()`. `manage.py audit_wallets`
checks every account (numbering without gaps, each entry starts where the last ended,
balance = sum); run it nightly once deployed. The client never sends amounts.

**Rewards (built in 1.8):** every reward goes through `rewards.engine.grant(user,
bundle, kind, idempotency_key)`: the claim and its ledger entries in one transaction,
once per key. Bundles hold currencies today; items and EXP join in Phase 2. The
reward-day is decided by the server clock: 00:00 Bahrain time by default
(`REWARD_DAY_TIMEZONE`, `REWARD_DAY_START_HOUR`). Daily login: once per reward-day, a
7-day cycle (100 → 400 gold, day 7: 500 gold + 5 diamonds; placeholders until admin
bundles), missing a day starts again at day 1; key `daily_login:{user}:{day}`.

### Redis keys

| Key | Type | Purpose | Expiry |
|---|---|---|---|
| `game:{id}:state` | string (JSON snapshot) | Live authoritative state | 24 h after game end |
| `game:{id}:events` | list (last 200) | Delta sync on reconnect | with state |
| `timers:turns` | sorted set (deadline) | Turn timer — *later*; today `Game.turn_deadline` (§2) | removed when fired |
| `ws:req:{user}:{req_id}` | string | Idempotent replies | 60 s |
| `rate:{user}:{bucket}` | counter | Rate limiting | window |
| `presence:{user}` | string | Online status (heartbeat) | 60 s |
| `mm:{mode}:{region}` | sorted set (joined_at) | Matchmaking queue | — |
| `lb:{season}:{scope}` | sorted set (rating) | Leaderboards (global/country/friends) | rebuilt from Postgres |

---

## 6. Game engine architecture

**Built in this step:** `backend/core/ludo_engine/`. No Django, no database, no clock,
no randomness inside — so it is fast to test, safe to replay, and portable to Dart.

### Positions

Each token stores **progress** from its own seat's start square:

| Progress | Meaning |
|---|---|
| −1 | in base |
| 0 – 50 | on the shared 52-square track (0 = own start square) |
| 51 – 55 | own home column (cannot be captured) |
| 56 | home (finished) |

`absolute_square(seat, progress) = (progress + 13 × seat) mod 52` — the square shared by
everyone. **Captures always compare absolute squares** (the old code compared progress).
Seats 0–3 = red, blue, green, yellow, matching the rotations in the Flutter `LudoPath`
(verified: blue starts at red's index 13, green 26, yellow 39). Safe squares: the four
start squares and the four stars (8 after each start): `0, 8, 13, 21, 26, 34, 39, 47`.

### Modules

| File | Responsibility |
|---|---|
| `board.py` | Geometry: track, seats, safe squares, progress → square |
| `rules.py` | `Rules` dataclass — every gameplay number is configurable and stored with the game |
| `state.py` | Immutable `GameState` / `PlayerState`, invariant checks, JSON snapshot (`to_dict` / `from_dict`) |
| `engine.py` | `new_game`, `roll`, `move`, `timeout`, `forfeit`, `apply_action`, `replay`, `legal_moves`, `standings` |
| `events.py` | Event types (= WebSocket event names) and `Transition(state, events)` |
| `dice.py` | `SecureDice` (OS crypto RNG) for the server, `ScriptedDice` for tests/replays |
| `bot.py` | Deterministic move choice for bots and timeout auto-moves |
| `errors.py` | Errors with stable codes (`not_your_turn`, `illegal_move`, …) sent to clients as-is |

### State model

```
GameState
 ├── game_id, version          # +1 per accepted action
 ├── status                    # playing | finished
 ├── phase                     # awaiting_roll | awaiting_move
 ├── players[]                 # turn order: player_id, seat, tokens[4], status, missed_turns, finish_place
 ├── current_index, turn_number
 ├── dice_value, consecutive_sixes
 ├── winner_id
 └── rules                     # the rules this game started with
```

### Rules implemented (defaults, all configurable)

- Enter on a 6; land on home exactly; cannot overshoot
- Extra turn on a 6, on a capture, on bringing a token home
- Three sixes in a row ends the turn
- No legal move → turn passes automatically
- Capture sends **every** opponent token on that square to base; safe squares and home columns protect
- Timeout: auto-roll (server dice) + bot move; 3 missed turns in a row → forfeit
- Forfeit/leave: player takes the lowest free place; last active player wins
- Two end modes: first player home wins (default), or play on for full ranking
- Unfinished players are ranked by progress (for rating changes later)

**Not implemented yet (TODO):** blocks (two same-colour tokens blocking a square),
team-mode victory, "enter and move" house-rule variants.

### Determinism and anti-cheat

The server rolls with `SecureDice`, then calls the engine with that value. Given the
same starting state and the same action list, the engine always produces the same
result — `replay()` rebuilds any game from `gameplay_game_action` for disputes or
after a Redis loss. The client can never send a dice value or a position: it only says
*"roll"* or *"move token 2"*, and the engine rejects anything illegal with a coded error.

### Tests (`python manage.py test ludo_engine` — 72 tests)

Board maths, rules validation, dice ranges, entering, extra turns, three sixes,
captures (including a regression test for the old bug), safe squares, home column,
exact finish, victory, ranking mode, timeouts, stale timers, forfeits, bot choices,
tampered snapshots, and **300 simulated full games** (2–4 players, both end modes,
random timeouts/forfeits) checking that versions always go up by one, opponents never
share an unsafe square, every game ends with a full ranking, and every game replays
exactly.

### Offline mode (Dart)

Offline play needs the same rules on the phone. ✅ Built in step 1.9:

- **Dart engine** — `features/ludo/domain/engine/` is a line-by-line copy of
  `ludo_engine` (board, rules, state, events, errors, engine, bot, dice) with the same
  actions (`roll`, `move`, `timeout`, `forfeit`, `applyAction`), the same event names
  and data, the same error codes and the same bot. Pure Dart: no Flutter, no clock.
- **Shared test vectors** — `ludo_engine/vectors.py` plays seeded games through the
  Python engine (whole games and games from random mid-game positions, ten rule
  variations, refused actions) and writes `shared/ludo/engine_vectors.json`: for every
  action the events, or the error code, the bot's choice and full state snapshots,
  plus the board numbers, the default rules, new-game setups and broken snapshots.
  `ludo_engine/tests/test_vectors.py` fails when the file is out of date and checks it
  covers every event, turn-end reason and error code; `test/ludo_engine_vectors_test.dart`
  replays every vector in Dart. Same vectors passing in both languages = same rules.
- **Changing a rule** — change Python first, run `python -m ludo_engine.vectors` (from
  `backend/core`), commit the new file; the Flutter tests then show where the Dart
  copy must change. The Python engine stays the authority: online games never use the
  Dart one.
- **Local play** — "Play on this phone" (`/local`, `/local/game`): 2–4 seats, each a
  person (pass-and-play on one screen) or the Majlis AI (`LudoBot`). The phone rolls
  with `Random.secure()`. Open signed out and when the server can't be reached
  (`appRedirect` lets `/local…` through in every state; Welcome and the offline splash
  have a "Play offline" button). Nothing is sent or saved: offline games never touch
  Gold, Diamonds, XP or ratings.

---

## 7. WebSocket architecture

### Connection

- **One socket per app session:** `wss://<host>/ws/v1/` — game, chat, presence and
  matchmaking share it (one auth, one reconnect, less battery).
- **Auth by first message**, not the URL (URLs end up in proxy logs):
  `{"type":"auth","data":{"access_token":"…"}}` within 5 s, else close `4408`.
- Heartbeat: client `ping` every 20 s; server marks presence; 2 missed pings = offline.
- Close codes: `4401` bad/expired token · `4403` forbidden · `4408` auth timeout · `4429` rate limited.

### Envelope

```jsonc
// client → server
{"v":1, "type":"move_token", "req_id":"5b1e…", "data":{"game_id":"…","token_index":2,"expected_version":41}}

// server → client: reply to that request
{"v":1, "type":"ack",   "req_id":"5b1e…", "data":{"version":42}}
{"v":1, "type":"error", "req_id":"5b1e…", "code":"illegal_move", "message":"token 2 cannot move 5"}

// server → client: broadcast
{"v":1, "type":"token_moved", "game_id":"…", "version":42, "data":{…}}
```

- **Idempotency:** `req_id` (UUID) is remembered for 60 s; a retried request gets the
  original reply and is not applied twice.
- **Ordering:** `expected_version` on game actions; mismatch → `stale_version` and the
  client resyncs.
- **Authorization:** every game action checks the user is a seated, active player of
  that game; chat checks membership and blocks.
- **Rate limits (initial):** game actions 10/s, chat 1/s (burst 5), subscribe 5/s.

### Event catalogue (v1)

| Group | Client → server | Server → client |
|---|---|---|
| Matchmaking | `join_queue {mode, ranked}` · `leave_queue` | `queue_status` · `match_found {room_id}` |
| Room | `create_room` · `join_room {code}` · `leave_room` · `player_ready` · `start_game` | `room_state` · `player_joined` · `player_left` · `game_starting {countdown}` · `game_started {snapshot}` |
| Game | `roll_dice` · `move_token {token_index}` · `forfeit` | `dice_result {value, movable_tokens}` · `token_moved` · `token_captured` · `token_finished` · `turn_started {deadline}` · `turn_ended {reason, extra_turn}` · `turn_warning` · `player_timeout` · `player_forfeited` · `player_finished` · `game_finished {winner_id, standings}` |
| Sync | `sync {game_id, version}` · `request_state {game_id}` | `state_delta {events[]}` · `state_snapshot {state}` |
| Chat | `send_message` · `typing_started` · `typing_stopped` · `mark_read` | `message_received` · `typing` · `read_receipt` |
| Presence | `ping` | `pong` · `friend_online` · `friend_offline` |

Game event names and payloads come straight from `ludo_engine.EventType`, each carrying
the state `version`.

### What step 1.11 built ✅ (`backend/core/realtime/`, app `lib/core/realtime/`)

The design above, with these decisions made while building it:

- **Server events name their channel:**
  `{"v":1,"type":"token_moved","channel":"game/42","version":7,"data":{…}}`, the same
  shape for every kind of channel (not a `game_id` field).
- **Channels** (`realtime/topics.py`; features register their own kinds):

  | Channel | Who | A new subscriber first gets | Then |
  |---|---|---|---|
  | `user/<player id>` | you only | `balances_changed {balances}` | `balances_changed` after every wallet change (on commit) |
  | `notifications/<player id>` | you only | — | nothing until Phase 5 |
  | `room/<room id>` (UUID) | seated members | `players_updated` (+ `game_started` once started) | `players_updated`, `game_started` |
  | `game/<game id>` (a number) | seated players | `state_snapshot` (with `version`) | the game's events, each with `version` |

  `chat/…` and anything else answer `unknown_channel` until built. The room and game
  messages are the lobby socket's, mirrored by `game.services.broadcast()` (still the
  one place that sends game messages); `game_started` and the snapshot now carry
  `game_id`, and `/api/me` → `active_room` carries `room_id`.
- **Sign-in:** the auth `ack` carries `{player_id, heartbeat_seconds: 20}`. Anything else
  first, or a bad message, closes 4401. Messages over 8 KB close 1009. The device
  session is checked again (on a ping) at most every 60 s, so a signed-out phone loses
  its socket.
- **Requests** other than `auth`, `ping`, `subscribe`, `unsubscribe` are handlers that
  features register (`realtime/handlers.py`; game actions in 1.12). Only handlers that
  change something use remembered replies: they need a `req_id`, and a retry within
  60 s (from any of the account's sockets) gets the first answer without running again.
  Refusals are remembered too; a server error is not, so a retry runs.
- **Rate limits** per account (all its sockets together), `REALTIME_RATE_LIMITS`:
  control (ping, unsubscribe) 10/s, subscribe 5/s, game 10/s, chat 5 per 5 s. Over the
  limit: `rate_limited`; three times over: close 4429.
- **Presence:** `presence:<user id>` lives 60 s, refreshed by every ping; a socket
  counter lets the last closing socket mark the account offline at once
  (`realtime/presence.py`: `is_online`, `online`).
- **App:** `RealtimeClient` (one per signed-in account, `realtimeClientProvider`) gets
  a fresh access token after a 4401, reconnects 1 s, 2 s, 4 s … 30 s (±20 %), drops a
  connection after two unanswered pings, and subscribes again to every channel still
  listened to. Features use `client.channel(name)` and `client.request(type)`. Home's
  balances follow `user/`.
- **Pushing from server code:** `realtime.publish(channel, type, data, version=…)`, after
  the change is committed (it never raises).

### What step 1.12 built ✅ (`backend/core/game/handlers.py`, app `RealtimeRoomSocket`)

Game actions over `/ws/v1/`. Every request names the game (`game_id`) or its room
(`code`); the server finds your seat from your account. All of them are in the `game`
rate-limit bucket.

| Request | Data | Ack |
|---|---|---|
| `roll_dice` | `{game_id\|code, expected_version?}` | `{version, dice, movable_token_ids}` |
| `move_token` | `{game_id\|code, token_id\|token_index, expected_version?}` | `{version, finished, winner}` |
| `game_action` | `{game_id\|code, action: {type, …}, expected_version?}` | `{version, …}` (any game) |
| `leave_game` | `{game_id\|code}` | `{left: true}` (a forfeit once started) |
| `request_state` | `{game_id\|code}` | the whole state (same as `game_started`, with `room_id`) |

- `roll_dice` / `move_token` are Ludo's (`wrong_game` otherwise). `game_action` takes
  only the types the game lists in `player_action_types` (Ludo: `roll`, `move`);
  timeouts, bot turns and forfeits stay the server's own. Any `player_id` sent is
  replaced by your seat.
- **Versions:** an engine action makes ONE new version, and all its events carry it
  (`dice_rolled` v5; `token_moved` + `turn_changed` v6). `expected_version` behind the
  game → `stale_version`, nothing applied.
- **Refusals** keep the engine's codes (`not_your_turn`, `wrong_phase`,
  `illegal_move`, …) plus `not_in_game`, `game_not_found`, `room_not_found`,
  `game_not_started`, `token_not_found`, `legacy_game`, `invalid_request`.
- **App:** `RealtimeRoomSocket` (made by `socketServiceFactoryProvider` while signed in)
  listens to `room/<room id>` and `game/<game id>` and hands the screens the lobby
  socket's message shapes, so the screens didn't change. It asks `request_state` when
  it opens (a channel another screen already listens to doesn't send its first
  events again), drops events older than the board, sends the same-version snapshot
  only once, and after a gap (a version more than one ahead) loads the whole state
  again; that reaches the screen as `game_started`. `GameSync` (`gameSyncProvider`)
  keeps the newest version per room; `ApiRoomRepository` sends roll and move over the
  socket with it as `expected_version`, and a `stale_version` refusal makes the socket
  load the state again. Socket refusals become `ApiException`s with the same code
  (`disconnected`/`timeout` → `network_error`).

**Room requests (step 1.13, `game/rooms.py`; PLATFORM §5 "What step 1.13 built"),** all
`{code, …}` in the `game` bucket: `set_ready {ready}`, `kick_player {player_id}`,
`lock_room {locked}`, `transfer_host {player_id}`, `room_settings {variant?,
options?}`, `invite_player {player_id: 9-digit}`, `decline_invite`, `start_game`
(`{status: starting|started}`), `rematch {want}` (`{next_room, seat_id}` once everyone
agreed). Creating and joining stay REST (`create-room`, `join-room`; joining checks
the status, kicks and the lock), and so does `start-game` (same rules). Refusal codes:
`not_host`, `not_in_room`, `host_always_ready`, `not_everyone_ready`, `game_starting`,
`game_already_started`, `player_kicked`, `room_locked`, `player_not_found`,
`cannot_invite_yourself`, `already_in_room`, `invalid_option`, `unknown_variant`,
`game_not_finished`, `room_closed`.

### Reconnection

```
socket drops → exponential backoff (1s, 2s, 4s … max 30s, with jitter)
→ reconnect → auth → server tells client its active game (if any)
→ client: sync {game_id, version: last version it applied}
→ server: state_delta (if those events are still in game:{id}:events)
          else state_snapshot
→ client renders; the turn timer kept running on the server the whole time
```

The client never "fixes" state itself. If anything looks wrong it sends `request_state`.

As built (1.14): the app's client remembers the newest version per channel and
re-subscribes with `{"channel": …, "since": <version>}`; a topic that can catch up
(`Topic.catch_up`; games) answers `state_delta` instead of its full first events, from
the messages kept on each `GameAction` (so it works after a server restart too).
After a gap the room socket sends `sync {code, version}` → `{kind: "delta", events…}`
or `{kind: "snapshot", …}`. Disconnects: PLATFORM §5 "What step 1.14 built".

### Seats belong to accounts (1.6)

Every room endpoint except `room-options` needs `Authorization: Bearer <access token>`
(§8). The server finds **your seat from your account**; the app never says which player
it is. Each account has at most one seat per room.

| Endpoint | Body | Notes |
|---|---|---|
| `POST /api/game/create-room/` | `{max_players, color?}` | 201 `{room, player}`; name = the account's name |
| `POST /api/game/join-room/` | `{code, color?}` | Joining a room you're in returns your seat (also after the start) |
| `POST /api/game/start-game/` | `{code}` | Host only (`403 not_host`) |
| `POST /api/game/roll-dice/` · `move-token/` | `{code}` · `{code, token_id}` | `403 not_in_room` if your account has no seat there |
| `POST /api/game/leave-room/` | `{code}` | Before the start: seat freed, host role passes on, an empty room closes. During a game: forfeit (through `services.perform`). Never fails for "not there" |

One game at a time: creating or joining while you're still playing a started game
gives `409 already_in_game` with its `room_code`; a room you were only *waiting* in is
left for you. `GET /api/me/` returns `active_room` (`code, seat_id, is_host,
max_players, started`) so the app can go straight back to it.

All errors are `{"error": "...", "code": "<stable_code>"}` (DRF's own errors too, via
`core/api_errors.py`); the app translates the `code`. `GET /api/game/room-options/`
gives the allowed player counts (from the engine), and the roll response and the
reconnect snapshot carry `movable_token_ids`, so the app never re-implements a rule.
The lobby socket (`/ws/lobby/<code>/`) is still read-only and unauthenticated (it only
broadcasts); `/ws/v1/` (step 1.11) has first-message auth and carries the same room and
game messages, and since 1.12 the app's game screens and actions use it.

### Migration from today

Today: actions go through REST (`/api/game/roll-dice/`, `move-token/`) and the socket
(`/ws/lobby/<code>/`) only broadcasts. Step 1.1 keeps those endpoints (so the app keeps
working) but runs them on the new engine and adds `version` to events. Step 1.11 added
`/ws/v1/` next to them; 1.12 moved the game screens and actions onto it. The REST
roll/move endpoints and the lobby socket still work (the app falls back to them only
when it has no live connection) and are removed once nothing uses them.

---

## 8. Authentication architecture

| Piece | Design |
|---|---|
| Identity | Our own `accounts.User` (UUID). Login methods link to it; a user can have several |
| Methods (order) | **Guest** (device-bound, keeps today's "type a name and play") → **email/password** → **Google** and **Apple** (server verifies the ID token signature, audience, expiry) → **phone OTP** (provider such as Twilio Verify or Firebase Phone Auth; server verifies) |
| Upgrade | A guest can attach email/Google/Apple later without losing progress |
| Tokens | Access JWT (HS256, 15 min, `sub` = user, `sid` = device session), kept in memory. Refresh token `<session id>.<secret>`, 30 days, only its SHA-256 stored, **rotated on every use**. The previous one still works for 2 minutes (the answer may have been lost on a bad network); after that it means a copied token → the whole session is ended |
| Storage | Refresh token in `flutter_secure_storage` (Keychain / Android Keystore). Nothing secret in the app bundle |
| Refresh | The app refreshes ~30 s before the access token runs out; one shared refresh call for everyone waiting. A Dio interceptor adds the token, and on `401 token_expired` refreshes once and retries; `session_revoked` → signed out. Offline → the request fails, the player stays signed in |
| Devices | `accounts_device_session` row per device; "log out other devices" revokes their refresh tokens |
| Password reset | A **6-digit code** emailed to the player and typed into the app (no links to open on a phone). Keyed hash stored, 1 hour, 5 tries, a new code replaces the old one, at most 5 emails per hour per account. Asking never reveals whether an email has an account. A new password signs the account out everywhere |
| WebSocket | First-message auth with the access token (§7); server re-checks on reconnect |
| Roles | Django groups: Super Admin, Admin, Moderator, Support, Event Manager. Django admin for staff at first |
| Protection | Rate limits per IP on sign-up, sign-in, refresh and reset (`DJANGO_NUM_PROXIES` behind a proxy) + per account: 10 wrong passwords in 15 minutes lock that email for 15 minutes. Unknown emails take as long as wrong passwords. Django's password rules (length, common, numbers only, too close to the email) with a code per rule. Password hashing (Django's PBKDF2), TLS everywhere, audit log on admin actions |
| Email | Development prints emails (reset codes) in the server's terminal. Production: an email provider's SMTP settings in `.env` (`EMAIL_BACKEND`, `EMAIL_HOST`, ...) — provider chosen before launch |
| Player ID | `User.player_id`: random 9-digit number (100 000 000–999 999 999) from `secrets`, unique, never changes or gets reused; random so it doesn't reveal how many players exist |

### API (built in 1.6–1.7)

| Endpoint | | |
|---|---|---|
| `POST /api/auth/guest/` | `{device_id, platform}` | 201 tokens + account. Rate limited per IP (`AUTH_GUEST_SIGNUP_RATE`, default 20/hour) |
| `POST /api/auth/register/` | `{email, password, device_id, platform}` | 201 tokens + account; 409 `email_taken`; 400 `invalid_input` with `fields.password` = `password_too_short` · `password_too_common` · `password_entirely_numeric` · `password_too_similar` |
| `POST /api/auth/login/` | `{email, password, device_id, platform}` | 200 tokens + account; 401 `invalid_credentials`; 429 `rate_limited` (+ `retry_after`) |
| `POST /api/auth/save-account/` | signed-in guest: `{email, password}` | 200 account (same Player ID, `is_guest` false); 409 `email_taken` · `already_saved` |
| `POST /api/auth/password-reset/` | `{email}` | 200 `{status: "sent"}` whether or not the email has an account |
| `POST /api/auth/password-reset/confirm/` | `{email, code, new_password}` | 200; 400 `invalid_code` · `code_expired` · `too_many_attempts` |
| `GET /api/profile/options/` | | `{avatars, languages, max_languages, name_min_length, name_max_length}` |
| `PATCH /api/me/profile/` | any of `{display_name, avatar, country, languages}` | 200 account; name errors in `fields.display_name`: `name_length` · `name_characters` · `name_not_allowed` |
| `GET /api/wallet/` | signed in | `{balances: {gold, diamond}}` (read only: no way to change them from the app) |
| `GET /api/wallet/transactions/?before=<id>` | signed in | `{transactions: [{id, reference, currency, amount, balance_after, type, created_at}], next}`, 30 per page, newest first |
| `GET /api/rewards/daily/` | signed in | `{reward_day, day, claimed_today, days: [{day, gold, diamond}], seconds_until_reset}` |
| `POST /api/rewards/daily/claim/` | signed in, no body | `{claimed: {day, gold, diamond}, balances, daily}`; 409 `already_claimed` |
| `POST /api/auth/refresh/` | `{refresh}` | 200 new tokens + account; 401 `invalid_refresh` · `refresh_expired` · `session_revoked` |
| `POST /api/auth/logout/` | signed in | 204; this device signed out |
| `POST /api/auth/logout-others/` | signed in | `{signed_out: n}` |
| `GET /api/me/` | signed in | `{player_id, is_guest, email, created_at, display_name, avatar, country, languages, level, xp, level_xp, next_level_xp, active_room}` |

Tokens answer `{access, refresh, token_type: "Bearer", access_expires_in, account}`.
Bad access tokens get 401 `token_expired`, `invalid_token` or `session_revoked`; no
token on a protected endpoint gets 401 `not_authenticated`. Every `invalid_input`
error lists a stable code per field in `fields` (never English), so the app can say
what to fix.

**Profiles (1.7):** made with every account (`profiles/signals.py`). Default name
`Player <last 4 digits of the Player ID>`, a built-in avatar picked from the Player ID.
Names: 2–20 characters, letters from any script, digits, spaces and `_ - . '`, at least
one letter, nothing that passes for the team (`admin`, `official`, ...). Avatars are
built-in pictures (keys in `profiles/choices.py`, art in the app); photo upload needs
image storage and moderation and comes later. Spoken languages: `en ar ur pa`. Level
from XP: each level needs 100 XP more than the one before (`profiles/levels.py`);
earning XP arrives in Phase 2.

### Splash flow

```
1. main(): theme, settings; app opens on the splash screen (logo ≥ 1.2 s)
2. Read refresh token from secure storage
3. None → Welcome ("Play as guest", email sign-in/up + forgotten password;
   Google / Apple when set up, else "coming soon")
4. Present → POST /api/auth/refresh → new tokens + account (with active_room)
5. active_room? → its waiting room, or the board if started. Else → Home
   Refused (invalid / expired / revoked) → clear tokens → Welcome
   Offline → stay on splash with "Try again" (the saved sign-in is kept)
```

The router sends signed-out players to Welcome, never shows Welcome to a signed-in
player, and keeps everything on the splash screen while the sign-in is checked.
Signing in any way (splash, email, reset) goes straight back to the account's
active room.

### Google and Apple sign-in (built in 1.15)

The phone asks Google or Apple; the server trusts only what it checks itself
(`accounts/social.py`): the ID token's RS256 signature against the provider's
published keys (cached an hour, fetched again for a new key id), `aud` = one of our
client IDs, `iss` = the provider, `exp` (one minute of leeway) and, for Apple, the
SHA-256 of the nonce the app made. Accounts are found by the provider's user id
(`SocialAccount.subject`), never by email.

| Endpoint | Body | Notes |
|---|---|---|
| `GET /api/auth/providers/` | – | `{google: bool, apple: bool}`: set up on this server |
| `POST /api/auth/social/<google\|apple>/` | `{id_token, nonce?, device_id, platform}` | 200 (known) / 201 (new account) tokens + account. A verified email that already has an account → 409 `email_taken` (sign in with it, then link) |
| `POST /api/me/link/<provider>/` | `{id_token, nonce?}` | Signed in. A guest keeps everything and is saved (`is_guest` false). `social_account_taken`, `already_linked` |
| `POST /api/me/unlink/<provider>/` | – | Refused as `last_sign_in_method` when nothing else signs in |

Refusals: `provider_not_configured` / `provider_unreachable` (503),
`unknown_provider` (404), `invalid_token`, `token_expired`, `wrong_audience`,
`wrong_issuer`, `invalid_nonce` (401). `/api/me` lists `linked` providers.

App: `core/auth/social_sign_in.dart` (`SocialSignIn`, plugins `google_sign_in` and
`sign_in_with_apple`). A button shows only when the server says the provider is set
up AND this build can use it (`socialProvidersProvider`); otherwise it stays "coming
soon". Google: Android and iOS. Apple: iOS (Android needs Apple's web flow, later).
Settings → Account lists linked providers (Unlink) and offers "Save with Google" to
guests / "Link Apple" to saved accounts.

**Setting it up (the owner's accounts; nothing works until this is done):**

1. **Google Cloud Console** → a project → OAuth consent screen (app name, support
   email) → Credentials → create OAuth client IDs:
   - *Web application* (its ID is the **server client ID**);
   - *Android*: package name (`applicationId` in `android/app/build.gradle.kts`) and
     the SHA-1 of each signing key (`./gradlew signingReport` for debug; Play Console
     → App integrity for release);
   - *iOS*: the bundle ID. Add its **reversed client ID** as a URL scheme in
     `ios/Runner/Info.plist` (`CFBundleURLTypes`).
2. **Apple Developer** → Identifiers → the app's App ID → enable *Sign in with Apple*;
   in Xcode → Runner → Signing & Capabilities → **+ Sign in with Apple**.
3. **Server** `.env`: `GOOGLE_CLIENT_IDS=<web>,<android>,<ios>` and
   `APPLE_CLIENT_IDS=<bundle id>` (comma-separated), then restart.
4. **App** build: `--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>` and, for iOS,
   `--dart-define=GOOGLE_IOS_CLIENT_ID=<ios client id>`.

Client IDs are not secrets (they ship inside the app); no client secret is needed.

## 9. Development environment

### Prerequisites

Python 3.12+, Flutter (stable, Dart ≥ 3.10), Docker Desktop, Git.

### Services (Postgres + Redis)

```bash
docker compose -f docker-compose.dev.yml up -d
```

### Backend

```bash
cd backend
python -m venv venv && source venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp ../.env.example ../.env       # SQLite + in-memory channel layer: no Docker needed
                                 # (DB_ENGINE=postgres / CHANNEL_LAYER=redis for the Docker services)
cd core
python manage.py migrate
uvicorn core.asgi:application --reload --host 0.0.0.0 --port 8000
```

> Plain `python manage.py runserver` does **not** serve WebSockets with the current
> settings. The turn timer starts automatically inside the uvicorn process.

### Tests

```bash
cd backend/core
python manage.py test                                    # everything (CI runs this on PostgreSQL)
python -m unittest discover -s ludo_engine/tests -t .    # engine only, without Django
```

### Flutter

```bash
cd frontend/dice_majlis_app
flutter pub get
flutter run                                                   # emulator: 10.0.2.2 / 127.0.0.1
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000   # real phone: computer's Wi-Fi IP
```

`lib/core/config/app_config.dart` derives the WebSocket address (`ws://` / `wss://`) from
`API_BASE_URL`; pass `WS_BASE_URL` only if sockets live elsewhere.

---

## 10. Phase-1 implementation plan

The prompt's Phase 1 aims at an offline prototype. This repo is already online, and the
online game has a bug that stops humans winning, so Phase 1 **fixes and stabilises the
working core first**, then builds the foundation around it. Every step leaves the app
runnable. Progress is tracked in [`planning.md`](planning.md).

| # | Step | Done when |
|---|---|---|
| 1.0 | ✅ **Engine** — `ludo_engine` + 72 tests | Tests pass under Django and plain unittest |
| 1.1 | ✅ **Wire engine into the current game.** `Game` gets `state` (JSON) + `version`; roll/move/bots call the engine; `SecureDice`; row lock on roll/move; events gain `version`. Flutter: fix `LudoPath` (drop `(6,14)`, add a home cell), allow moves up to progress 56, read `square`/`progress` from the server | A human can bring all tokens home and win; captures happen only on the same square; existing screens unchanged |
| 1.2 | ✅ **Turn timer** — deadline on `Game` (same transaction as state), sweep in the server process or `run_turn_timers`; `turn_changed` carries `seconds_left`; auto-move; 3 misses → forfeit. Flutter countdown in the turn chip + idle messages | An idle player is auto-played, then removed; game never freezes |
| 1.3 | ✅ **Dev & CI foundation** — uvicorn + `psycopg` in requirements; production guard in settings (refuses dev secret key / `*` hosts / in-memory layer when `DEBUG` is off) instead of a settings split; `CHANNEL_LAYER=memory` for Redis-free development; `API_BASE_URL`/`WS_BASE_URL` via `--dart-define`; GitHub Actions running backend tests on PostgreSQL + `flutter analyze` + `flutter test`; `CLAUDE.md` | Fresh clone runs with the documented commands; CI green on every push |
| 1.4 – 1.15 | The rest of Phase 1 follows the **master prompt's** priority list: Flutter architecture, main navigation, accounts + Player ID, profile, currency foundation, local play, game platform layer, WebSocket v1, online multiplayer on v1, private rooms v2, reconnection, Google/Apple sign-in. **Current list: [planning.md](planning.md).** | |

**After Phase 1:** player system, Ludo variants and team mode, multiplayer at scale,
social, competition, economy, events, VIP & collections, admin, polish, production,
new games — order in [planning.md](planning.md), designs in [PLATFORM.md](PLATFORM.md),
[SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md) and [ROYAL_VIP_ECONOMY.md](ROYAL_VIP_ECONOMY.md).
