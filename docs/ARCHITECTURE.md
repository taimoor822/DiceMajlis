# Dice Majlis — Technical Foundation

> Status: living document. Last updated 2026-11-15.
> Covers the 10 foundation items from the master build prompt, adapted to the code
> that already exists in this repository. Profiles, Majlis rooms and the gift economy
> are designed in [SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md); the current phase order is in
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
- Flutter screens: splash, home, create room, join room, waiting room, board, win

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
| API/WS URLs hard-coded to `127.0.0.1` / `10.0.2.2` | `api_service.dart`, `socket_service.dart` | A real phone can't reach the server | 1.3 |
| No ASGI server or Postgres driver in `requirements.txt` | `backend/requirements.txt` | WebSockets need Daphne/Uvicorn, and `DB_ENGINE=postgres` needs `psycopg`, both installed by hand | 1.3 |
| Create Room always sends `red`, Join Room always sends `blue` | `create_room_screen.dart`, `join_room_screen.dart` | 3rd/4th players share a colour and a board path | ✅ 1.1 (server reassigns clashing colours to free seats) |
| `DATABASE_URL=sqlite:////abs/path` loses its leading `/` | `core/settings.py` | Absolute SQLite paths fail to open | 1.3 |

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

Moving today's files (no behaviour change, step 1.4):

| Today | Moves to |
|---|---|
| `app/app.dart`, `app/routes.dart` | `app.dart`, `core/routing/app_router.dart` |
| `app/theme.dart` (neon green) | `core/theme/` — replaced by Majlis gold/dark tokens |
| `services/api_service.dart` | `core/network/api_client.dart` + `features/multiplayer/data/` |
| `services/socket_service.dart` | `core/websocket/socket_client.dart` |
| `services/session_storage*.dart` | `core/storage/` |
| `game/ludo_path.dart` | `features/ludo/domain/board_geometry.dart` |
| `screens/<x>/` | `features/<x>/presentation/` |
| `widgets/*` | `shared/widgets/` |
| `providers/*.dart`, `models/player_model.dart`, `models/room_model.dart`, `utils/constants.dart` | Deleted — they are empty (0 bytes) |

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
    │   └── tests/             # 72 tests incl. 300 simulated full games
    ├── game/                  # rooms + REST + WS; services.py = the only code that changes game state
    │                          # (split into rooms/ + gameplay/ later)
    ├── users/                 # existing, empty → replaced by accounts/
    │
    │  planned apps (each added in the phase that needs it)
    ├── accounts/              # P1 users, devices/sessions, JWT, social + phone login
    ├── profiles/              # P1 display name, avatar, frame, stats summary
    ├── realtime/              # P2 socket envelope, auth, rate limits, idempotency
    ├── gameplay/              # P2 Redis game store, action log, turn-timer worker
    ├── matchmaking/           # P2 queues, rating windows
    ├── ranking/               # P3 ratings, leagues, seasons, leaderboards
    ├── chat/  social/         # P4 rooms, messages, friends, blocks, reports, presence
    ├── wallet/  rewards/      # P5 ledger, purchases, missions, achievements, pass
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
| 1 | `accounts_user` | id, username (unique, case-insensitive), email (unique, nullable), phone (unique, nullable), is_guest, is_active, last_login |
| 1 | `accounts_device_session` | user, device_id, platform, refresh_jti, last_seen, revoked_at — powers "log out other devices" |
| 1 | `profiles_profile` | user (1:1), display_name, avatar, country, xp, level |
| 1→2 | `gameplay_game` | id, room, mode (2p/4p/team), ranked, status, rules (JSONB), initial_state (JSONB), final_state (JSONB), winner, started_at, ended_at |
| 2 | `gameplay_game_player` | game, user, seat, place, rating_before/after — unique(game, seat), unique(game, user) |
| ✅ 1.1 | `game_gameaction` (→ `gameplay_game_action`) | game, version, action (JSONB), created_at — unique(game, version). **The audit log for disputes and replays** |
| 2 | `rooms_room` | id, code (unique), host, mode, visibility, max_players, status |
| 3 | `ranking_rating` | user, season, rating, rd (Glicko), wins, losses, games, streak, league |
| 3 | `ranking_season`, `ranking_league` | |
| 4 | `chat_room`, `chat_message` | message: room, sender, type (text/emoji/system), body, created_at — index(room, created_at) |
| 4 | `chat_conversation`, `chat_read_marker` | 1:1 chats, read status |
| 4 | `social_friendship`, `social_friend_request`, `social_block`, `moderation_report` | unique pairs, both directions checked |
| 5 | `wallet_account` | user, currency (coins/diamonds), balance (cached), version |
| 5 | `wallet_transaction` | account, amount (+/−), reason, ref_type/ref_id, **idempotency_key (unique)**, balance_after |
| 5 | `rewards_*`, `missions_*`, `achievements_*`, `pass_*` | |
| 6 | `tournaments_tournament`, `_participant`, `_match` | |
| all | `audit_log` | actor, action, target, data, ip — admin and sensitive actions |

**Wallet rule:** balances only change through `wallet.services.post_transaction()`,
inside a DB transaction with `SELECT … FOR UPDATE` on the account, writing one
immutable `wallet_transaction` row. The same `idempotency_key` twice = no double credit.
The client never sends amounts.

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

Offline play needs the same rules on the phone. Plan (step 1.8): port the engine to
Dart under `features/ludo/domain/engine/` with the same API, and export the Python
test cases as JSON "test vectors" (`state + action → expected state + events`) that
both test suites run. Same vectors passing in both languages = same rules. Offline
games never touch online coins or rating.

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

### Migration from today

Today: actions go through REST (`/api/game/roll-dice/`, `move-token/`) and the socket
(`/ws/lobby/<code>/`) only broadcasts. Step 1.1 keeps those endpoints (so the app keeps
working) but runs them on the new engine and adds `version` to events. Phase 2 adds
`/ws/v1/`, moves actions onto the socket, then removes the old endpoints.

---

## 8. Authentication architecture

| Piece | Design |
|---|---|
| Identity | Our own `accounts.User` (UUID). Login methods link to it; a user can have several |
| Methods (order) | **Guest** (device-bound, keeps today's "type a name and play") → **email/password** → **Google** and **Apple** (server verifies the ID token signature, audience, expiry) → **phone OTP** (provider such as Twilio Verify or Firebase Phone Auth; server verifies) |
| Upgrade | A guest can attach email/Google/Apple later without losing progress |
| Tokens | Access JWT, 15 min, kept in memory. Refresh token, 30 days, rotated on every use, old one blacklisted |
| Storage | Refresh token in `flutter_secure_storage` (Keychain / Android Keystore). Nothing secret in the app bundle |
| Refresh | Dio interceptor: on 401, one shared refresh call (lock), then retry the queued requests; refresh fails → logout |
| Devices | `accounts_device_session` row per device; "log out other devices" revokes their refresh tokens |
| Password reset | Emailed one-time token (Django's token generator), expires in 1 hour |
| WebSocket | First-message auth with the access token (§7); server re-checks on reconnect |
| Roles | Django groups: Super Admin, Admin, Moderator, Support, Event Manager. Django admin for staff at first |
| Protection | Login rate limits per IP + account, password hashing (Django's Argon2/PBKDF2), TLS everywhere, audit log on admin actions |

### Splash flow

```
1. Init: load env config, theme, locale, error reporting
2. Read refresh token from secure storage
3. None → Login (or "Play as guest")
4. Present → POST /api/auth/refresh → new access token
5. Load /api/me (profile, wallet summary, active game)
6. Active game? → resume board. Else → Home
   Any failure in 4–5 → clear tokens → Login
```

---

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
cp ../.env.example ../.env       # SQLite by default. For the Docker Postgres:
                                 #   set DB_ENGINE=postgres and pip install "psycopg[binary]"
cd core
python manage.py migrate
pip install "uvicorn[standard]"                       # WebSocket server; joins requirements in 1.3
uvicorn core.asgi:application --reload --host 0.0.0.0 --port 8000
```

> Plain `python manage.py runserver` does **not** serve WebSockets with the current
> settings. The turn timer starts automatically inside the uvicorn process.

### Tests

```bash
cd backend/core
python manage.py test ludo_engine                        # engine only (no DB/Redis needed)
python -m unittest discover -s ludo_engine/tests -t .    # same, without Django
```

### Flutter

```bash
cd frontend/dice_majlis_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator
```

On a **real phone**, use your computer's LAN IP (e.g. `http://192.168.1.20:8000`) and add
it to `DJANGO_ALLOWED_HOSTS`. (The app reads `API_BASE_URL` after step 1.3; today the URL
is hard-coded in `api_service.dart` and `socket_service.dart`.)

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
| 1.3 | **Dev & CI foundation** — Daphne + `psycopg` in requirements, settings split (dev/prod), `API_BASE_URL`/`WS_BASE_URL` via `--dart-define`, Docker Compose, GitHub Actions running backend tests + `flutter analyze` | Fresh clone runs with the documented commands; CI green on every push |
| 1.4 | **Flutter foundation refactor** (no behaviour change) — Riverpod, GoRouter, Freezed; move files to `core/` `shared/` `features/`; Majlis theme tokens (Dark + Light); l10n scaffold (en, ar, ur); delete empty files | Same screens and flows, new structure; no hard-coded colours in moved widgets |
| 1.5 | **Guest accounts + JWT** — `accounts` app, `/api/auth/guest`, `/refresh`, `/me`; Flutter splash restores session; room APIs use the logged-in user | Reinstall-free relaunch keeps the same player; name no longer typed each game |
| 1.6 | **Email/password + profile** — register, login, reset password, profile edit (name, avatar) | Guest can upgrade to an email account without losing anything |
| 1.7 | **Home dashboard v1** — header (avatar, name, coins/diamonds placeholders marked *coming soon*), mode tiles (2P, 4P, private room, offline), bottom nav | Home is the hub; unbuilt modes are clearly labelled, not fake |
| 1.8 | **Offline mode** — Dart engine port + shared JSON test vectors; vs AI and pass-and-play | Plays with airplane mode on; Dart tests pass on the same vectors as Python |
| 1.9 | **Google + Apple sign-in** | Both work on real devices; accounts link to existing guests |

**Phase 2 preview:** `/ws/v1/` single socket with the §7 protocol, presence service,
domain-event outbox (needed by the social features), Redis game store with
version-checked writes, matchmaking queue, reconnection with `state_delta`,
multiplayer tests (disconnect, duplicate request, latency).

**After Phase 2:** identity, economy and Majlis rooms — see
[SOCIAL_MAJLIS.md §17](SOCIAL_MAJLIS.md#17-build-order).
