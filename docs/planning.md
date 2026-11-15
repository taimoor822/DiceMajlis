# Dice Majlis — Progress Tracker

Architecture and the reasoning behind each step: [ARCHITECTURE.md](ARCHITECTURE.md)
(foundation) and [SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md) (profiles, Majlis rooms, gifts).
Rule: build vertically, keep the app runnable after every step.

## Phase 1 — Foundation

- [x] **1.0** Pure-Python Ludo engine (`backend/core/ludo_engine/`) + tests
- [x] **1.1** Wire the engine into the current game (fixes: humans can't win, wrong-square captures, safe squares, colour clashes) + Flutter board path fix
- [x] **1.2** Server turn timer, auto-move, 3 misses → forfeit, countdown in the app
- [ ] **1.3** Dev & CI: Daphne + psycopg, settings split, `--dart-define` URLs, GitHub Actions
- [ ] **1.4** Flutter refactor to `core/ shared/ features/` with Riverpod, GoRouter, Freezed, l10n; Majlis theme tokens (navy, teal, turquoise, emerald, gold, sand + rarity colours)
- [ ] **1.5** Guest accounts + JWT + splash session restore + **permanent 9-digit Player ID**
- [ ] **1.6** Email/password, password reset, basic profile (name, avatar, country, spoken languages)
- [ ] **1.7** Home dashboard v1
- [ ] **1.8** Offline mode: Dart engine + shared test vectors, vs AI, pass-and-play
- [ ] **1.9** Google + Apple sign-in

## Phase 2 — Real-time and multiplayer v2

- [ ] `/ws/v1/` single socket: first-message auth, envelope, `req_id` idempotency, rate limits
- [ ] Presence service (online status, used by profiles and rooms)
- [ ] Domain-event outbox + worker (connects games, gifts, achievements, moments, rankings)
- [ ] Redis game store, matchmaking, reconnection with `state_delta`

## Phase 3 — Identity ([SOCIAL_MAJLIS §17](SOCIAL_MAJLIS.md#17-build-order))

- [ ] **S1** Profile page, Player ID copy/search, languages, privacy; follow, friends, block, report
- [ ] **S2** Statistics from real online games (bot games excluded)
- [ ] **S3** Achievements engine + first achievements
- [ ] **S4** Cosmetics: favourite dice, nameplates, frames (own + equip)

## Phase 4 — Economy and gifts

- [ ] **S5** Gift catalog managed in admin
- [ ] **S6** Wallet + ledger: gold coins and diamonds (earned and granted only, no real money yet)
- [ ] **S7** Send gifts to profiles: atomic, idempotent; gifts shown on profile
- [ ] **S8** Gift animation engine (5 rarity tiers, combos, fallback)

## Phase 5 — Majlis rooms

- [ ] **S9** Persistent social rooms: create, join, background, room info
- [ ] **S10** Members with server-side search and roles
- [ ] **S11** Room chat + moderation basics (filter, report, block, mute, kick, delete)
- [ ] **S12** Presence and online counts
- [ ] **S13** Mic slots (no audio yet), room gifting, licensed music

## Phase 6 — Room social loop

- [ ] **S14** Moments
- [ ] **S15** Contribution ranking (24h / 7d)
- [ ] **S16** Attraction ranking
- [ ] **S17** Room levels, XP and unlocks
- [ ] **S18** Room events with prizes
- [ ] **S19** Full moderation and audit
- [ ] **S20** Live-ops admin (scheduled gifts, events, banners)

## Later

- [ ] **7** Competitive: ratings, leagues, seasons, leaderboards (fills league fields on profiles)
- [ ] **8** Tournaments
- [ ] **9** Monetisation: diamond purchases via App Store / Google Play, VIP, Majlis Pass, spend limits
- [ ] **10** Voice (WebRTC SFU) and polish: animations, performance, analytics, accessibility, Arabic / Urdu / Punjabi

> Social comes before competitive, following the master prompt's priority:
> quality → reliability → multiplayer → social → competition → monetisation → scale.

## Known TODOs in the engine

- Blocks (two same-colour tokens blocking a square)
- Team-mode victory
- House-rule variants ("enter and move")
