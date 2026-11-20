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
  core/                    settings (env-driven), asgi.py (starts turn timer), urls
  ludo_engine/             PURE Python rules engine + tests (no Django inside)
  game/                    rooms, REST views, socket consumer, services.py, timers.py, bots
frontend/dice_majlis_app/  Flutter app: lib/core (config, network, websocket, theme,
                           routing, l10n), lib/shared/widgets, lib/features/<x>/
                           {data,domain,presentation}; server address in
                           lib/core/config/app_config.dart
docs/                      plans and designs
.github/workflows/ci.yml   CI: backend tests on Postgres + flutter analyze/test
```

## Rules that must not be broken

1. **Server-authoritative.** The app never sends dice values, positions, prices or
   balances. It asks ("roll", "move token 2", "send gift X"); the server decides.
2. **One write path for games.** All game state changes go through
   `game/services.py::perform()` → `ludo_engine`. Never write `Game.state`, `Token`
   rows or game broadcasts anywhere else.
3. **`ludo_engine` stays pure:** no Django, no database, no clock, no randomness.
   The server rolls with `SecureDice` and passes values in; that keeps games replayable.
4. **Money and items (when built):** balances and item counts change only through the
   wallet / item ledgers, append-only, with idempotency keys, inside one DB transaction.
   Every reward goes through the one `grant()` engine. Purchases are granted only after
   server verification with Apple/Google (SOCIAL_MAJLIS §5–7, ROYAL_VIP_ECONOMY §3–6).
   Privileges are checked only through the entitlement engine — no `if user.isVip`.
   VIP/Royal never affect ratings, leagues or matchmaking (no pay-to-win).
5. **No hard-coded gameplay numbers or prices in Flutter.** Rules live in
   `ludo_engine/rules.py`; gift prices and catalogs come from the server.
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
python manage.py test                                  # everything (~120 tests)
python -m unittest discover -s ludo_engine/tests -t .  # engine only, no Django
python manage.py run_turn_timers --once                # one timer sweep

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
- The analyzer **infos** on newer Flutter are deprecation notices, not errors.
- Generated files (`*.freezed.dart`, `*.g.dart`, `lib/core/l10n/generated/`) are
  committed; CI fails if they're stale. User-facing text goes in `app_en.arb`,
  colours in `core/theme/` (read with `context.majlis`), never inline in widgets.
- Widget tests use `test/helpers/fakes.dart` (fake room API + fake sockets via
  provider overrides); no test touches the network.
- Backend tests use `GAME_BOTS_INLINE=True` (bots run synchronously) and the in-memory
  channel layer. Script dice by patching `game.services.SecureDice.roll`.
- Engine token index ↔ DB token: tokens of a player sorted by `str(id)` (the Flutter
  board uses the same order).
- Games started before the engine (`Game.state` is NULL) return `409 legacy_game`.
- Until accounts (1.6), seat actions need the device's `player_token` from
  create/join (`game/player_auth.py`); tests get it via `GameApiTestCase.post`.
  API errors are `{"error", "code"}`; the app maps `code` to text in
  `core/l10n/api_error_text.dart` and never shows the server's English.
- Navigation: Home + five tabs in a GoRouter `StatefulShellRoute` (`app_router.dart`,
  `features/navigation/`). Unbuilt sections use `ComingSoonPage` / `SoonBadge`.
  Device settings use `sharedPreferencesProvider` (null in tests unless overridden).
- The app keeps the current room (`roomSessionProvider`) only in memory on phones
  (web uses browser storage); persistent sessions arrive with accounts (step 1.6).

## Status

See `docs/planning.md` (master roadmap, 13 phases, Phase 1 = playable foundation).
Done: engine (1.0), live game on engine (1.1), turn timer (1.2), dev setup + CI (1.3),
Flutter architecture + Majlis theme (1.4), main navigation (1.5).
Next: 1.6 accounts with Player ID, 1.7 email + profile, 1.8 currency foundation.

Dice Majlis is a **platform**: new games (Domino, Jackaroo) plug in through the game
registry (PLATFORM §3) — keep game-specific code out of shared systems.

Decided: real money yes (two currencies + VIP via App Store / Google Play).
Open owner decisions and their defaults: table at the end of `docs/planning.md`.
Ask when the phase that needs one starts.
