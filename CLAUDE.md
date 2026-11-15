# CLAUDE.md — Dice Majlis

Guide for Claude Code sessions on this repo. Read this first, then the docs below.

**Dice Majlis**: multiplayer Ludo with a social Majlis around it (profiles, social
rooms, gifts, rankings). Flutter app + Django/Channels backend. Owner: Taimoor Aziz
(@taimoor822), who is building it while learning. Explain changes in plain words,
keep replies short (often read on a phone), and always say how to try the change.

## Read before working

| Doc | What it holds |
|---|---|
| `docs/planning.md` | **Current step** and progress checklist — start here |
| `docs/ARCHITECTURE.md` | Stack decisions, system design, engine, WebSocket protocol, auth, dev setup |
| `docs/SOCIAL_MAJLIS.md` | Design for profiles, Majlis rooms, wallet/ledger, gifts (phases 3–6) |
| `README.md` | What works today, how to run it |

The owner may send an updated plan. When the plan changes, update `docs/planning.md`
(and the design docs if needed) before building.

## Repo map

```
backend/core/              Django project (run manage.py from here)
  core/                    settings (env-driven), asgi.py (starts turn timer), urls
  ludo_engine/             PURE Python rules engine + tests (no Django inside)
  game/                    rooms, REST views, socket consumer, services.py, timers.py, bots
frontend/dice_majlis_app/  Flutter app (lib/app/config.dart = server address)
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
4. **Money (when built):** balances change only through the wallet ledger service,
   append-only, with idempotency keys, inside one DB transaction (SOCIAL_MAJLIS §5–7).
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
python manage.py test                                  # everything (~110 tests)
python -m unittest discover -s ludo_engine/tests -t .  # engine only, no Django
python manage.py run_turn_timers --once                # one timer sweep

# Flutter (from frontend/dice_majlis_app)
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<computer-wifi-ip>:8000   # real phone
flutter analyze --no-fatal-infos
flutter test
```

Local config is in `.env` (copy `.env.example`). `CHANNEL_LAYER=memory` runs without
Redis (one server process only). CI runs the backend on PostgreSQL.

## Gotchas

- **Line endings:** several Dart files use CRLF or mixed endings. Never run
  `dart format` on whole folders; format only files you created, and edit existing
  files without converting their line endings (keep diffs minimal).
- Newer Flutter versions rewrite `analysis_options.yaml` and `pubspec.lock` on
  `pub get`. Revert those unless the change is intended.
- The ~16 analyzer **infos** are deprecation notices from newer Flutter, not errors.
- Backend tests use `GAME_BOTS_INLINE=True` (bots run synchronously) and the in-memory
  channel layer. Script dice by patching `game.services.SecureDice.roll`.
- Engine token index ↔ DB token: tokens of a player sorted by `str(id)` (the Flutter
  board uses the same order).
- Games started before the engine (`Game.state` is NULL) return `409 legacy_game`.
- The app keeps the current game only in memory on phones (web uses browser storage);
  persistent sessions arrive with accounts (step 1.5).

## Status

See `docs/planning.md`. Done: engine (1.0), live game on engine (1.1), turn timer
(1.2), dev setup + CI (1.3). Next: 1.4 Flutter restructure + Majlis theme, then 1.5
accounts with permanent Player ID.

Open owner decisions (answer when that phase starts): real-money diamonds, gift
cash-out (assumed no), voice in v1, minimum age, Punjabi script.
