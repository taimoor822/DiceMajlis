# Dice Majlis — Progress Tracker

Architecture and the reasoning behind each step: [ARCHITECTURE.md](ARCHITECTURE.md)
(foundation), [SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md) (profiles, Majlis rooms, gifts) and
[ROYAL_VIP_ECONOMY.md](ROYAL_VIP_ECONOMY.md) (store, VIP, Royal levels, items).
Rule: build vertically, keep the app runnable after every step.

## Phase 1 — Foundation

- [x] **1.0** Pure-Python Ludo engine (`backend/core/ludo_engine/`) + tests
- [x] **1.1** Wire the engine into the current game (fixes: humans can't win, wrong-square captures, safe squares, colour clashes) + Flutter board path fix
- [x] **1.2** Server turn timer, auto-move, 3 misses → forfeit, countdown in the app
- [x] **1.3** Dev & CI: uvicorn + psycopg, production settings guard, Redis-free dev option, `--dart-define` server address, GitHub Actions (Postgres), `CLAUDE.md`
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
- [ ] **S4** Item system (catalog, inventory, item ledger, equip) with cosmetics first: favourite dice, nameplates, frames

## Phase 4 — Economy and gifts

- [ ] **S5** Gift catalog managed in admin
- [ ] **S6** Wallet + ledger: gold, diamonds, fragments (earned and granted only, no real money yet)
- [ ] **S6b** Reward engine: one `grant()` for every reward, claims, server reward-day + daily login reward
- [ ] **S6c** Entitlement engine: privilege catalog, grants, inheritance, admin overrides
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

### Phase 9 — Store and purchases ([ROYAL_VIP_ECONOMY §21](ROYAL_VIP_ECONOMY.md#21-build-order))

- [ ] **M1** Store catalog (admin) + Store screen with real store prices
- [ ] **M2** Gold and diamond purchases, server-verified (Apple / Google), refunds
- [ ] **M3** Promotions: first-purchase bonus, limited packages, regions, recharge tickets
- [ ] **M4** Purchase and transaction history

### Phase 10 — VIP and Royal

- [ ] **M5** Subscription engine + VIP Knight / Baron (tiers are config)
- [ ] **M6** VIP daily rewards with streaks
- [ ] **M7** Royal EXP ledger, levels, idempotent level-up
- [ ] **M8** Royal privileges + Royal Level screen
- [ ] **M9** Royal Reward Tower
- [ ] **M10** VIP/Royal in profiles, rooms, chat and social sorting

### Phase 11 — Premium items and extras

- [ ] **M11** Magic cards and props
- [ ] **M12** Fragment Exchange
- [ ] **M13** Super Value Surprise (free draws, odds shown)
- [ ] **M14** Daily Gift Commission
- [ ] **M15** Visitor history (+ stealth visit)
- [ ] **M16** Chat privileges: voice messages, stickers, GIFs, styles
- [ ] **M17** Support tickets with priority
- [ ] **M18** Economy dashboard and balancing

### Then

- [ ] **12** Voice (WebRTC SFU) and polish: animations, performance, analytics, accessibility, Arabic / Urdu / Punjabi

> Social comes before competitive, following the master prompt's priority:
> quality → reliability → multiplayer → social → competition → monetisation → scale.

## Known TODOs in the engine

- Blocks (two same-colour tokens blocking a square)
- Team-mode victory
- House-rule variants ("enter and move")
