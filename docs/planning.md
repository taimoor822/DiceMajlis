# Dice Majlis — Progress Tracker

Architecture and the reasoning behind each step: [ARCHITECTURE.md](ARCHITECTURE.md).
Rule: build vertically, keep the app runnable after every step.

## Phase 1 — Foundation

- [x] **1.0** Pure-Python Ludo engine (`backend/core/ludo_engine/`) + 71 tests
- [x] **1.1** Wire the engine into the current game (fixes: humans can't win, wrong-square captures, safe squares, colour clashes) + Flutter board path fix
- [ ] **1.2** Server turn timer, auto-move, 3 misses → forfeit, countdown ring
- [ ] **1.3** Dev & CI: Daphne + psycopg, settings split, `--dart-define` URLs, GitHub Actions
- [ ] **1.4** Flutter refactor to `core/ shared/ features/` with Riverpod, GoRouter, Freezed, Majlis theme, l10n
- [ ] **1.5** Guest accounts + JWT + splash session restore
- [ ] **1.6** Email/password, password reset, profile
- [ ] **1.7** Home dashboard v1
- [ ] **1.8** Offline mode: Dart engine + shared test vectors, vs AI, pass-and-play
- [ ] **1.9** Google + Apple sign-in

## Later phases

- [ ] **2** Online multiplayer v2: `/ws/v1/` protocol, Redis game store, matchmaking, reconnection
- [ ] **3** Competitive: ratings, leagues, seasons, leaderboards, match history
- [ ] **4** Social: global/game/private chat, friends, presence, block/report
- [ ] **5** Economy: wallet ledger, coins/diamonds, rewards, missions, Majlis Pass, cosmetics
- [ ] **6** Tournaments
- [ ] **7** Polish: animations, performance, analytics, crash reporting, anti-cheat, accessibility, localisation

## Known TODOs in the engine

- Blocks (two same-colour tokens blocking a square)
- Team-mode victory
- House-rule variants ("enter and move")
