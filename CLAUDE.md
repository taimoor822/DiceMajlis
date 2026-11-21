# CLAUDE.md — Dice Majlis

Guide for Claude Code sessions on this repo. Read this first, then the docs below.

**Dice Majlis**: multiplayer Ludo with a social Majlis around it (profiles, social
rooms, gifts, rankings). Flutter app + Django/Channels backend. Owner: Taimoor Aziz
(@taimoor822), who is building it while learning. Explain changes in plain words,
keep replies short (often read on a phone), and always say how to try the change.

## Read before working

| Doc | What it holds |
|---|---|
| `docs/planning.md` | **Master roadmap**: current step, build order, open decisions — start here |
| `docs/ARCHITECTURE.md` | Stack decisions, system design, engine, WebSocket protocol, auth, dev setup |
| `docs/SOCIAL_MAJLIS.md` | Design for profiles, Majlis rooms, wallet/ledger, gifts (S-steps) |
| `docs/ROYAL_VIP_ECONOMY.md` | Store/purchases, VIP, Royal levels, items, rewards, entitlements (M-steps) |
| `docs/PLATFORM.md` | Multi-game platform, variants, rooms, matchmaking, ratings, tournaments, missions, events, collections, shop, feed, chat, notifications, admin |
| `README.md` | What works today, how to run it |

The owner may send an updated plan. When the plan changes, update `docs/planning.md`
(and the design docs if needed) before building.

## Repo map

```
backend/core/              Django project (run manage.py from here)
  core/                    settings (env-driven), asgi.py (starts turn timer), urls,
                           api_errors.py (one {"error","code"} shape)
  accounts/                User (UUID + 9-digit Player ID), DeviceSession, JWT +
                           rotating refresh tokens, guest + email sign-in, save
                           guest account, password reset code, /api/me;
                           social.py + SocialAccount = Google/Apple sign-in
  profiles/                Profile (name, avatar key, country, languages, XP),
                           level curve, PATCH /api/me/profile/; xp.py = XP ledger
                           (add_xp) + XP from games
  wallet/                  gold + diamond accounts, append-only ledger, post() /
                           reverse(), admin adjustments, audit_wallets command
  rewards/                 grant() engine, reward-day (00:00 Bahrain), daily login
  events/                  domain-event outbox: emit() in the change's transaction,
                           on(kind, handler); handlers run after commit, sweep retries
  items/                   one item system: catalog, inventory, append-only item
                           ledger, equip cosmetics (dice, board, frame), expiry
  stats/                   statistics from real online games (results + totals)
  progress/                progress engine: achievements (metrics, tiers, unlocks,
                           rewards through grant()); missions later
  ludo_engine/             PURE Python rules engine + tests (no Django inside);
                           vectors.py writes the shared test vectors
  game_platform/           PURE game registry: GameEngine contract, register/get_game,
                           Ludo adapter (variant classic), catalog(); toy game in tests
  game/                    rooms, REST views, socket consumer, services.py, timers.py, bots;
                           tables/ = per-game extras (Ludo: Token rows, socket messages);
                           topics.py = the room/ and game/ socket channels;
                           handlers.py = game + room requests on /ws/v1/ (roll_dice, …);
                           rooms.py = private rooms (status, ready, host, invites, rematch);
                           connections.py = dropped players, catch-up, restart safety
  realtime/                /ws/v1/ (the app's one socket): protocol, topics (channels),
                           publish(), handlers (requests), limits, presence, consumer
frontend/dice_majlis_app/  Flutter app: lib/core (config, network, realtime, websocket, theme,
                           routing, l10n), lib/shared/widgets, lib/features/<x>/
                           {data,domain,presentation}; server address in
                           lib/core/config/app_config.dart
shared/ludo/               engine_vectors.json: the rules as data; Python and Dart
                           engines must both pass it (generated, never edit by hand)
docs/                      plans and designs
.github/workflows/ci.yml   CI: backend tests on Postgres + flutter analyze/test
```

## Rules that must not be broken

1. **Server-authoritative.** The app never sends dice values, positions, prices or
   balances. It asks ("roll", "move token 2", "send gift X"); the server decides.
2. **One write path for games.** All game state changes go through
   `game/services.py::perform()` → the room's engine from `game_platform`
   (`get_game(game_type)`). Never write `Game.state`, `Token` rows or game
   broadcasts anywhere else, and never import a game engine in shared code: look it
   up in the registry.
3. **`ludo_engine` stays pure:** no Django, no database, no clock, no randomness.
   The server rolls with `SecureDice` and passes values in; that keeps games replayable.
4. **Money and items (when built):** balances and item counts change only through the
   wallet / item ledgers, append-only, with idempotency keys, inside one DB transaction.
   Every reward goes through the one `grant()` engine. Purchases are granted only after
   server verification with Apple/Google (SOCIAL_MAJLIS §5–7, ROYAL_VIP_ECONOMY §3–6).
   Privileges are checked only through the entitlement engine — no `if user.isVip`.
   VIP/Royal never affect ratings, leagues or matchmaking (no pay-to-win).
5. **No hard-coded gameplay numbers or prices in Flutter.** Rules live in
   `ludo_engine/rules.py`; gift prices and catalogs come from the server. The one
   exception is the Dart engine for offline games (`features/ludo/domain/engine/`),
   a copy kept identical by the shared test vectors: change Python first.
6. **Build vertically, one plan step at a time.** Keep the app runnable after every
   step. Don't rewrite unrelated working code.
7. **No fake features.** Anything not built is labelled TODO / "coming soon", never
   faked with hard-coded data.
8. **Original design and assets only** — no other app's names, art or branding.
9. Positions are **progress per seat** (−1 base, 0–50 track, 51–55 home column,
   56 home). Compare players with `absolute_square()`, never raw progress.

## Workflow

- One branch per plan step, e.g. `phase1/accounts`. Never commit to `main`; the
  owner merges pull requests.
- Finishing a step: tests pass → tick it in `docs/planning.md` → update docs/README
  if behaviour changed → commit with a clear message → push the branch.
- Ask the owner before anything hard to undo (deleting data, real money, external
  services, changing the plan's order).

## Commands

```bash
# Backend (from backend/core)
pip install -r ../requirements.txt
python manage.py migrate
uvicorn core.asgi:application --reload --host 0.0.0.0 --port 8000   # NOT runserver (no WebSockets)
python manage.py test                                  # everything (~410 tests)
python manage.py check_achievements                    # unlock achievements players already qualify for
python -m unittest discover -s ludo_engine/tests -t .  # engine only, no Django
python -m unittest discover -s game_platform/tests -t .  # game registry only, no Django
python manage.py run_turn_timers --once                # one timer sweep
python manage.py audit_wallets                         # every balance = its ledger
python -m ludo_engine.vectors                          # rewrite shared/ludo/engine_vectors.json after a rules change

# Flutter (from frontend/dice_majlis_app)
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<computer-wifi-ip>:8000   # real phone
flutter analyze --no-fatal-infos
flutter test
dart run build_runner build --delete-conflicting-outputs   # after editing a Freezed model
flutter gen-l10n                                            # after editing lib/core/l10n/app_en.arb
```

Local config is in `.env` (copy `.env.example`). `CHANNEL_LAYER=memory` runs without
Redis (one server process only). CI runs the backend on PostgreSQL.

## Gotchas

- **Line endings:** several Dart files use CRLF or mixed endings. Never run
  `dart format` on whole folders; format only files you created, and edit existing
  files without converting their line endings (keep diffs minimal).
- The project (and CI) uses **Flutter 3.38.7**. Newer Flutter versions rewrite
  `analysis_options.yaml` and `pubspec.lock` on `pub get`, and newer package
  versions need Flutter 3.47+. Revert those unless the change is intended.
  `path_provider_foundation` is kept below 2.6 in `pubspec.yaml`: 2.6+ brings
  build hooks (`objective_c`) that `build_runner` can't compile on 3.38.
- The analyzer **infos** on newer Flutter are deprecation notices, not errors.
- Generated files (`*.freezed.dart`, `*.g.dart`, `lib/core/l10n/generated/`) are
  committed; CI fails if they're stale. User-facing text goes in `app_en.arb`,
  colours in `core/theme/` (read with `context.majlis`), never inline in widgets.
- Widget tests use `test/helpers/fakes.dart` (fake room API, fake sign-in API,
  in-memory token store, fake sockets via provider overrides); no test touches the
  network. `testApp()` opens signed in (a saved refresh token); pass
  `tokens: MemoryTokenStore()` for a signed-out start.
- Backend tests use `GAME_BOTS_INLINE=True` (bots run synchronously), the in-memory
  channel layer and a local-memory cache (rate limits). Script dice with
  `GameApiTestCase.dice(6, 3, ...)` (it swaps `services.SERVER_RANDOM` for a
  `game_platform.ScriptedRandom`). `GameApiTestCase.post(..., player_id=X)` signs in
  as the account holding seat X; without it, as a brand-new guest.
- Engine token index ↔ DB token: tokens of a player sorted by `str(id)` (the Flutter
  board uses the same order).
- Games started before the engine (`Game.state` is NULL) return `409 legacy_game`.
- Accounts (1.6): every room endpoint needs `Authorization: Bearer <access>`; the
  server finds the seat from the account (`Player.user`), never from the request
  body. Leaving goes through `services.leave_room` (forfeit via `perform()`).
  App side: `core/auth/` (`AuthController`, `TokenStore` = secure storage,
  `AuthApi`), `core/network/auth_interceptor.dart` adds/refreshes tokens; the
  router (`appRedirect`) sends signed-out players to `/welcome`. API errors are
  `{"error", "code"}`; the app maps `code` to text in
  `core/l10n/api_error_text.dart` and never shows the server's English.
- Navigation: five tabs in a GoRouter `StatefulShellRoute` (`app_router.dart`,
  `features/navigation/`); Battle, the centre tab, is the Home lobby at `/home`. Unbuilt sections use `ComingSoonPage` / `SoonBadge`.
  Device settings use `sharedPreferencesProvider` (null in tests unless overridden).
- The current room (`roomSessionProvider`) lives in memory only; after a restart
  the splash screen puts it back from `GET /api/me` → `active_room`.
- A dev database from before 1.6 can't migrate (new user model): delete
  `backend/core/db.sqlite3` and run `migrate` again.
- Profiles (1.7): every account gets one (`profiles/signals.py`); read and change it
  through `profiles/services.py`. The level is computed from XP on the server
  (`profiles/levels.py`), never in the app. Avatars are keys (`profiles/choices.py`);
  the app draws them (`shared/widgets/player_avatar.dart`). Validation errors return a
  code per field (`core/api_errors.py`); the app reads them with
  `ApiException.fieldError(...)`.
- Emails (password reset codes) print in the server terminal in development
  (console backend); tests read `django.core.mail.outbox`.
- The router only re-runs its redirect when the *kind* of sign-in state changes
  (signed in / out / loading), not when the account is updated (profile edits).
- Country names and the picker come from `country_picker`; its names load through
  `core/l10n/country_names.dart` (synchronous, so the first frame isn't blank).
- Wallet (1.8): currencies are `gold` and `diamond`. Balances change only through
  `wallet.services.post()` (or `reverse()`); ledger rows can't be saved twice or
  deleted (`LedgerIsAppendOnly`). Rewards go through `rewards.engine.grant()` with an
  idempotency key; add a new reward kind to `LEDGER_TYPES` and a new ledger type to
  `TransactionType`. Daily reward amounts are placeholders in `rewards/daily.py`.
  Tests pin the clock by passing `now=` (reward-day = Bahrain time).
- App economy state: `balancesProvider` (set it from any answer that brings new
  balances), `dailyRewardProvider`. Widget tests get wallet/reward fakes from
  `fakeNetwork()`, or `fakeEconomy()` when pumping a screen alone.
- Offline games (1.9): the Dart engine in `features/ludo/domain/engine/` copies the
  Python one exactly (same events, error codes, bot). After changing a rule in
  Python, run `python -m ludo_engine.vectors`, commit the JSON, then make
  `test/ludo_engine_vectors_test.dart` pass. `features/local_play/` runs games on the
  phone (`LocalGameController`: secure dice, AI turns, token walks); tests override
  `localDiceProvider` (`ScriptedDice`) and `localPlayTimingProvider`
  (`LocalPlayTiming.instant`). `/local` pages are open signed out and offline. Offline
  games never call the server or touch money/XP/ratings.
- Game platform (1.10): rooms and games have `game_type` + `variant` (default
  `ludo`/`classic`). A new game = pure engine + adapter (`game_platform/contract.py`)
  + `register()` in `game_platform/__init__.py` (+ a table in `game/tables/` if it
  needs extra rows/messages) + an app `GameModule` in `gameModulesProvider`
  (`features/games/game_registry.dart`). Engines do the server's part in
  `prepare_action` (dice, bot choice, timeouts) with the random source passed in.
  The roll/move REST endpoints are Ludo's (`wrong_game` otherwise). App tests fake
  the catalog with `FakeGameCatalogRepository` (Ludo Classic by default).
- Board picture (`assets/board/majlis_board.svg`): its colours must follow the seat
  order (red enters at the bottom, then blue left, green top, yellow right, as in
  `LudoPath`). `LudoBoardView` draws board + tokens for offline games; the online
  `GameBoardScreen` still has its own drawing (to move onto `LudoBoardView` later).

- Realtime (1.11): `/ws/v1/` lives in `realtime/` (ARCHITECTURE §7 "What step 1.11
  built"). Push from server code with `realtime.publish.publish(channel, type, data,
  version=…)` after the change is committed; game messages still go only through
  `game.services.broadcast()` (it feeds both the lobby socket and the v1 `room/` and
  `game/` channels). New channel kinds: a `Topic` + `topics.register()` (in the app's
  `ready()`); new socket requests: `realtime.handlers.register(type, fn, bucket=…)`.
  Socket tests use `realtime/tests/socket_client.py` (not `channels.testing`, which
  needs daphne) in a `TransactionTestCase`. App: `core/realtime/` `RealtimeClient`
  (`realtimeClientProvider`, null when signed out); listen with
  `client.channel(RealtimeChannels.user(id))`. Tests get a `FakeRealtimeServer` from
  `fakeNetwork()`/`testApp(realtime: …)` and can `push()` events. In widget tests,
  don't `await` a broadcast-stream `cancel()` (it finishes outside the fake clock and
  the test hangs), and stop the client inside the test, not in `addTearDown` (its ping
  timer must be gone before Flutter's pending-timer check). A `ProviderContainer`
  that outlives the widget tree overrides `realtimeClientProvider` with null.
- Online games (1.12): game requests are `game/handlers.py` (`roll_dice`, `move_token`,
  `game_action`, `leave_game`, `request_state`; ARCHITECTURE §7 "What step 1.12
  built"). A new game's player actions go through `game_action`, limited to its
  engine's `player_action_types`. The app's room screens get a `RealtimeRoomSocket`
  (same message shapes as the old lobby socket) and `ApiRoomRepository` sends roll/move
  over the socket with `expected_version` from `GameSync`. All events of one engine
  action share ONE version. Backend handler tests: `game/test_handlers.py` (call
  `realtime_handlers.get(type).fn(Context(user, "s"), data)`); app tests:
  `test/online_game_test.dart` (`FakeRealtimeServer.handlers[type]` answers requests;
  throw `RealtimeException(code)` to refuse). The REST roll/move endpoints and the
  lobby socket remain as a fallback until removed.
- Private rooms (1.13): room rules live in `game/rooms.py` (raise `RoomError(code)`);
  `Room.status` WAITING/READY/STARTING/PLAYING/FINISHED/CLOSED (keep `is_started` in
  step: True from PLAYING on). Every room change ends with `rooms.broadcast_room(room)`
  (`players_updated` + `room_updated`). The host is always ready; guests set
  `is_ready`. Starting = `rooms.request_start` (countdown `GAME_START_COUNTDOWN_SECONDS`,
  0 in `GameApiTestCase`; `rooms.start_due_rooms()` runs in the timer sweep). A rematch
  is a NEW room (old one CLOSED, `next_room`). Custom rules are `Variant.options`
  (`RoomOption`), passed to `new_game(options=…)`; the app names them through
  `GameModule.ruleName/ruleValue`. Test guests: `GameApiTestCase.join()` marks them
  ready (`ready=False` to skip). Tests: `game/test_rooms.py`, app
  `test/private_rooms_test.dart`.
- Reconnection (1.14): `realtime.presence.listen(fn)` hears an account go offline /
  come back (presence counts sockets by id with a last-seen time); `game/connections.py`
  marks `Player.disconnected_at` and broadcasts `player_disconnected/_reconnected`.
  Every `GameAction` keeps its broadcast `messages`: `services.game_delta(game, since)`
  builds `state_delta`; topics may implement `catch_up(user, key, since)` (used when a
  subscribe has `since`). App: `RealtimeClient` re-subscribes with `since`;
  `RealtimeRoomSocket` applies `state_delta` / `sync` deltas through the same version
  checks. Fake server: `FakeRealtimeServer.catchUp` and `.subscribes`. Tests:
  `game/test_reconnect.py`, app `test/online_game_test.dart`.
- Google/Apple (1.15): `accounts/social.py` verifies ID tokens (tests sign their own
  with an RSA key and patch `social._fetch_jwks`; never hit the network). Client IDs
  come from `GOOGLE_CLIENT_IDS` / `APPLE_CLIENT_IDS` (empty = not configured). Never
  join accounts by email. App: `core/auth/social_sign_in.dart`; tests fake it with
  `FakeSocialSignIn` (`testApp(social: …)`) and `FakeAuthApi.serverProviders`.
  Real sign-in needs the owner's Google Cloud / Apple setup (ARCHITECTURE §8).
- Domain events + XP (2.1): `events.outbox.emit(kind, payload)` inside the change's
  transaction; register handlers with `events.outbox.on(kind, fn)` in an app's
  `ready()`. Handlers must be idempotent (an event may arrive twice) and run inside
  one transaction with "processed" (a failure undoes them; the timer sweep retries).
  `game_finished` is emitted only by `services.perform()` (payload: `game/results.py`;
  `counts` = real game, 2+ accounts and no bots — bot games never give XP, stats or
  achievements). XP changes only through `profiles.xp.add_xp()` (append-only
  `XpEntry`, idempotency key, optional daily cap, pushes `xp_gained` on `user/<id>`);
  `Profile.xp` is read-only in the admin. Amounts are placeholders at the top of
  `profiles/xp.py`. Tests: `TestCase` never runs commit hooks, so wrap the action in
  `self.captureOnCommitCallbacks(execute=True)` or call `dispatch_pending(min_age_seconds=0)`.
  App: `accountLiveProvider` (`features/profile/domain/account_live.dart`, watched by
  the app root) updates the account from `xp_gained` and `cosmetics_changed`;
  `xpGainsProvider` keeps game XP by room code for the result dialog.
- Items (2.2): `items/` = one item system for every item kind (ROYAL_VIP_ECONOMY §4).
  Change ownership only through `items.services` (`grant`, `change`; append-only
  `ItemTransaction` with an idempotency key, quantity never below 0; cosmetics are
  owned once). Starter items (`is_starter`) are owned by everyone without rows. Wear
  with `services.equip(user, slot, code)` (checks slot + ownership); with nothing
  chosen, dice/board fall back to the first starter, a frame may be empty. Time-limited
  copies expire in the timer sweep (`expire_due`) and come off. The admin grants
  through `ItemAdjustment`. `/api/me` and every room's `players` carry `cosmetics`
  (`{slot: asset key}`). The catalog starts from migration `items/0002`. App:
  `features/cosmetics/` (Customise screen at `/home/profile/customise`,
  `inventoryProvider`); looks per asset key in `core/theme/cosmetic_looks.dart`
  (unknown keys = plain look); `PlayerAvatar(frame:)`, `DiceWidget(skin:)`,
  `BoardSkinRim` (first child of a board `Stack`; the board keeps its size). The die
  shows the skin of whoever's turn it is; the board skin is your own. Tests:
  `items/tests/`, app `test/cosmetics_test.dart` with `FakeItemsRepository`.
- Statistics (2.3): `stats/` listens to `game_finished` (real games only) and writes
  one `PlayerGameResult` per account per game (unique, so a game counts once) and
  updates `PlayerStats` per game type in the same transaction (1st place = win; every
  other place and leaving = loss; streaks). Then it emits `player_stats_changed`
  (`user_id`, `stats`, `total`) for achievements and pushes `stats_changed`.
  `GET /api/me/stats/` (totals, per game type, last 10 results; the win rate is worked
  out on the server). App: `features/stats/` (`statsProvider`, `StatsCard` on the
  Profile); tests use `FakeStatsRepository` (`testApp(stats: …)`).
- Achievements (2.4): `progress/` is the progress engine (missions reuse it later).
  `Achievement` (admin catalog: metric, icon key, rarity, hidden) with
  `AchievementTier`s (threshold + reward bundle). Metrics are read live from where
  the server keeps them (`progress/metrics.py`: games_played, wins, best_win_streak
  from stats; level from XP) — never stored twice. Handlers: `player_stats_changed`
  and `xp_added` (emitted by `add_xp`) call `services.check(user, metrics)`, which
  unlocks reached tiers once (`AchievementUnlock` unique per user+tier), pays the
  reward through `rewards.grant(kind="achievement")`, emits `achievement_unlocked`
  (for moments/notifications later) and pushes it on `user/<id>` (with `room_code`
  when a game did it). After adding achievements, run `manage.py
  check_achievements`. Event chains (game_finished → stats → achievements) run right
  after each commit; in tests call `dispatch_pending(min_age_seconds=0)` a few times.
  App: `features/achievements/` (`/home/profile/achievements`, `achievementsProvider`,
  `achievementUnlocksProvider`); the app root shows a note per unlock through
  `rootMessengerKeyProvider` (`core/ui/messenger.dart`); the game result lists the
  game's unlocks. Tests: `progress/tests/`, app `test/achievements_test.dart`
  (`FakeAchievementsRepository`).
- Running the backend tests locally without Redis: `CHANNEL_LAYER=memory
  DJANGO_DEBUG=true python manage.py test` (as CI does).

## Status

See `docs/planning.md` (master roadmap, 13 phases, Phase 1 = playable foundation).
Done: engine (1.0), live game on engine (1.1), turn timer (1.2), dev setup + CI (1.3),
Flutter architecture + Majlis theme (1.4), main navigation (1.5), guest accounts with
Player ID + session restore (1.6), email sign-in + password reset + basic profile (1.7),
gold + diamonds wallet ledger, grant() and daily reward (1.8), local play on a Dart
engine checked by shared test vectors, vs AI and pass-and-play (1.9), game platform
layer: registry + game_type/variant on server and app (1.10), WebSocket v1: one
authenticated socket, channels, rate limits, remembered replies, presence, live
balances (1.11), online games on v1: actions over the socket, versioned sync (1.12),
private rooms v2: ready, host controls, invites, custom rules, countdown, rematch (1.13),
reconnection: seat kept, away/back, state_delta catch-up, restart-safe (1.14),
Google + Apple sign-in, built and waiting for the owner's provider setup (1.15).
Phase 1 is complete. Phase 2: domain events + XP and levels from games (2.1), item
system + cosmetics (2.2), statistics (2.3), achievements (2.4). Next: reward
bundles with items and XP (2.5), see `docs/planning.md`.

Dice Majlis is a **platform**: new games (Domino, Jackaroo) plug in through the game
registry (PLATFORM §3) — keep game-specific code out of shared systems.

Decided: real money yes (two currencies + VIP via App Store / Google Play); the
currencies are **Gold** and **Diamonds**.
Open owner decisions and their defaults: table at the end of `docs/planning.md`.
Ask when the phase that needs one starts.
