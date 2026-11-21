# Dice Majlis — Master Roadmap

The single build order for the whole project, following the **master development
prompt**: a minimum complete playable foundation first, then each system layered on
top. Rule: build vertically, keep the app runnable after every step.

| Design | Covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stack, system, engine, WebSocket protocol, auth, dev setup |
| [PLATFORM.md](PLATFORM.md) | Multi-game platform, variants, rooms, matchmaking, ratings, tournaments, missions, events, collections, shop, feed, chat, notifications, admin, production |
| [SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md) | Profiles, Majlis rooms, wallet, gifts (steps **S1–S20**) |
| [ROYAL_VIP_ECONOMY.md](ROYAL_VIP_ECONOMY.md) | Store, VIP, Royal, items, rewards, entitlements (steps **M1–M18**) |

S- and M-codes point to the build tables in those docs; this file decides **when**.

---

## Phase 1 — Playable foundation

The master prompt's priority list (items 1–15), in build order.

- [x] **1.0** Ludo rules engine: dice, turns, movement, safe squares, captures, home path, extra turns, sixes rules, win detection (prompt items 6–9)
- [x] **1.1** Live online game on the engine: backend game model, server dice, action log (items 11, 13 — first version)
- [x] **1.2** Turn timer, AFK handling, idle players removed
- [x] **1.3** Dev setup + CI: requirements, production guard, Redis-free dev, server address setting, GitHub Actions, `CLAUDE.md`
- [x] **1.4** Flutter architecture: `core/ shared/ features/`, Riverpod, GoRouter (guarded routes), Freezed, design system with the Majlis theme (dark + light), localisation-ready (item 1)
- [x] **1.5** Main navigation: **Events · Game Hub · Battle · Chat · Social**, Battle (centre) = the Home lobby; today's room flow lives in Game Hub; unbuilt sections say "coming soon" (item 3)
- [x] **1.6** Accounts: guest login + JWT + **permanent 9-digit Player ID** + session restore; rooms use the account (item 2)
- [x] **1.7** Email/password, password reset, basic profile: avatar, name, Player ID, country, languages, level/XP (items 2, 4)
- [x] **1.8** Currency foundation: wallet ledger (**Gold** and **Diamonds**), daily login reward, balances on Home (item 5, **S6**). The daily reward needs the reward engine's core now (one `grant()`, claims, reward-day boundary); Phase 2 adds admin-made bundles, items and streak options to it
- [x] **1.9** Local play: Dart engine + shared test vectors; vs AI and pass-and-play (item 10). The Dart engine (`features/ludo/domain/engine/`) replays every vector the Python engine exports (`shared/ludo/engine_vectors.json`); "Play on this phone" (Game Hub, or Welcome/splash with no account or no server) runs 2–4 seats, each a person or the Majlis AI, with no Gold, Diamonds or rating. The board picture's red and blue were swapped to match the seat order
- [x] **1.10** Game platform layer: `game_type` / `variant` + engine registry on server and app, ready for Domino/Jackaroo (PLATFORM §3). Server: pure `game_platform` package (contract, registry, Ludo adapter with variant Classic), rooms and games store `game_type`/`variant`, the game service, bots and turn timer run any registered game (tested with a toy second game), Ludo's extras live in `game/tables/`, `GET /api/game/catalog/`. App: `features/games/` registry (`GameModule` per game type), Game Hub built from the catalog, create room sends the game, the board is picked by game type
- [x] **1.11** WebSocket foundation v1: one socket, first-message auth, subscriptions (`game/` `room/` `chat/` `user/` `notifications/`), envelope, idempotency, rate limits, presence (item 12). Server: `realtime/` app at `/ws/v1/` (auth message within 5 s, else 4408; bad token 4401; ping every 20 s; per-account rate limits, 4429 when far over; remembered replies for requests that change something; presence in the cache; a signed-out device loses its socket within a minute). Channels `user/<player id>` (balances live), `notifications/<player id>` (empty until Phase 5), `room/<room id>` and `game/<game id>` (same messages as the lobby socket, plus the state version; a new subscriber gets the current state first). `chat/` answers `unknown_channel` until chat is built (Phase 5). App: `core/realtime/` `RealtimeClient` (one connection while signed in, token refresh on 4401, reconnect 1 s → 30 s with jitter, re-subscribes), Home balances follow `user/`. The game screens still use the lobby socket until 1.12
- [x] **1.12** Online multiplayer on v1: game actions over the socket, versioned sync (item 13). Server: `game/handlers.py` answers `roll_dice`, `move_token` (token id or index), `game_action` (any game's own player actions, from `player_action_types` in the contract), `leave_game` and `request_state` (the whole state) on `/ws/v1/`; the seat comes from the account; an optional `expected_version` that is behind gives `stale_version`. The snapshot carries `room_id`. App: the room screens use `RealtimeRoomSocket` (`room/` + `game/` channels, drops what the board already has, loads the whole state again after a gap), roll and move go over the socket with the board's version (`GameSync`), and a `stale_version` refusal reloads the board. The REST roll/move endpoints and the lobby socket stay as a fallback for now (removed once nothing uses them)
- [x] **1.13** Private rooms v2: WAITING → READY → STARTING → PLAYING → FINISHED → CLOSED, ready system, host controls, invites, custom rules, rematch, leave (item 14). Server: `game/rooms.py` (room status, guests' ready flags (the host always is, so a host alone may start and the AI joins), host controls: remove (no coming back unless invited again), lock (invited players only), pass the host role, custom rules from the variant's options (`Variant.options`, checked by `check_options`; Ludo: turn time 15/30/60 s, captures, extra turn on a six, play on for every place), a 3-second start countdown run by the turn-timer sweep, invites by Player ID (`RoomInvite`, pushed on `user/<id>`, `GET /api/game/invites/`), rematch when everyone still in the finished room says yes: a new room with the same people and colours, the old one CLOSED and pointing to it). Socket requests in `game/handlers.py`; `room/` sends `room_updated`, `player_kicked`, `rematch_started`. App: the waiting room shows ready, the status and countdown, the rules (names from the game's module), host menus, lock and invite; Home lists invites live; the game-over dialog offers Play again. Deep links for invites wait for a web domain (later)
- [x] **1.14** Reconnection: seat kept, `player_disconnected` / `player_reconnected`, `state_delta` sync, safe across server restarts (item 15). Server: `game/connections.py` hears from presence (now per socket, so sockets of a dead server stop counting) when an account goes offline or comes back, marks its seats (`Player.disconnected_at`) and tells the room; every action keeps the messages it broadcast (`GameAction.messages`), so a returning player re-subscribes with `since` and gets `state_delta` (or the whole state when too far behind); `sync` asks the same on demand; after a restart the sweep restarts bot turns and marks seats whose sockets died. App: the client re-subscribes with the last version per channel, the room socket applies missed events (and asks `sync` after a gap), the board shows "Away" players and waits while this phone reconnects
- [x] **1.15** Google + Apple sign-in. Server: `accounts/social.py` checks the ID token (RS256 signature from the provider's keys, audience = our client IDs, issuer, expiry, Apple nonce); `POST /api/auth/social/<provider>/` signs in (same Google/Apple user → same account; never joined by email), `POST /api/me/link/<provider>/` attaches it to the signed-in account (a guest keeps everything and is saved), unlink refused when it's the only way in, `GET /api/auth/providers/`. App: Welcome buttons and Settings → Account (Save with Google / Link Apple / Unlink), shown only when the server and the build are set up. **Owner setup needed** (Google Cloud OAuth clients, Apple "Sign in with Apple"): ARCHITECTURE §8 "Google and Apple sign-in". Apple on Android (web flow) later

## Phase 2 — Player system

- [x] **2.1** XP and account levels from games. Server: a **domain-event outbox** (`events/`: `emit()` writes a `DomainEvent` in the same transaction as the change, handlers run after the commit, the timer sweep retries what's left; SOCIAL_MAJLIS §11); `services.perform()` emits `game_finished` when a game ends (`game/results.py`: places, seats, accounts, and `counts` = a real game: 2+ accounts, no bots); `profiles/xp.py` gives XP through an append-only `XpEntry` ledger (`add_xp`, once per idempotency key, daily cap) and pushes `xp_gained` on `user/<id>`. Placeholder amounts: 20 per game played to the end, +30 for 1st, +10 for 2nd with 3+ players, 0 when you forfeit, 500 a day from games. App: the level updates live; the result dialog shows "+N XP", level ups, or "games with the AI don't give XP"
- [x] **2.2** Item system + basic customisation: dice skins, board skins, frames; equip (**S4**). Server: `items/` — `ItemDefinition` catalog (every item kind; cosmetics first, admin-managed), `InventoryItem` + append-only `ItemTransaction` (idempotency keys, never below 0, time-limited copies expire in the timer sweep), `EquippedCosmetic` one per slot, `ItemAdjustment` for admin grants; starter set owned by everyone (2 dice, 2 boards, 1 frame) and 8 more items for achievements/rewards later; `GET /api/me/items/`, `POST /api/me/items/equip/`; `cosmetics` in `/api/me` and in every room's players; pushes `inventory_changed` / `cosmetics_changed`. App: Profile → Customise (dice, board, frame with previews), frame around your avatar (Home, Profile), the die shows the skin of whoever is playing (online) or yours (offline), your board skin draws a rim around the board
- [x] **2.3** Statistics from real online games, bot games excluded (**S2**). Server: `stats/` handles `game_finished` (only `counts` games: 2+ accounts, no bots): one `PlayerGameResult` per account per game (unique: a game counts once) and `PlayerStats` per game type in the same transaction — games, wins (1st place), losses, games left, wins in a row and best streak; emits `player_stats_changed` for achievements and pushes `stats_changed`; `GET /api/me/stats/` (totals, per game type, last 10 results, win rate worked out on the server). App: a Statistics card on the Profile (games, wins, win rate, best streak, current streak, latest results), live after each game
- [x] **2.4** Progress engine: achievements first (**S3**); missions reuse it in Phase 8. Server: `progress/` — admin-managed `Achievement`s on a metric (games played, wins, best win streak, account level; read live from stats and XP, never stored twice), each with tiers (threshold + reward bundle), hidden ones; `player_stats_changed` and `xp_added` check them; an unlock happens once (`AchievementUnlock` unique), pays through `grant()` (new ledger type `reward_achievement`), emits `achievement_unlocked` and pushes it to the account; `GET /api/me/achievements/`; `manage.py check_achievements` after catalog changes. First catalog (placeholder rewards): Regular Guest (1/10/100/1000 games), Victories (1/10/50 wins), On a Roll (3/5/10 in a row), Rising Star (level 5/10/20), and a hidden Majlis Legend (100 wins). App: Profile → Achievements (progress bars, tiers with rewards, hidden count), a note when one unlocks, the game result lists the game's unlocks
- [x] **2.5** Reward engine: admin-made bundles, items and EXP in `grant()`, streak options, reward history (**S6b**; its core — `grant()`, claims, reward-day — arrived in 1.8). Server: bundles hold gold, diamonds, XP and items (time-limited or for good), checked by `check_bundle`; `grant()` writes claim + wallet + XP + items in one transaction or nothing; admin `RewardBundle`s; the daily cycle is admin data (`DailyRewardDay` → bundle) with streak options (`DailyRewardSettings`: a missed day restarts or carries on; after the last day loop or stay); day 7 now also gives 20 XP and lends the Pearl dice for 7 days; achievements now also give cosmetics (Night Sky dice for 10 wins, Lantern Glow frame for 3 in a row, Sandstone board at level 5, Palm Arch frame for 100 games, Midnight board for 10 in a row, Falcon Crest + Ruby for the hidden Majlis Legend); `RewardClaim.source`; `GET /api/rewards/history/`. App: rewards show XP and items everywhere (daily card, claim note, achievements, unlock notes), the daily card follows the server's cycle (`next_day`, the miss rule), Wallet → Reward history
- [x] **2.6** Entitlement engine foundation: privilege catalog, grants, overrides (**S6c**). Server: `entitlements/` — the one place that answers "may this account do X, how much?" (`engine.has` / `engine.value`, cached a minute and forgotten when inputs change); `Privilege` catalog seeded from ROYAL_VIP_ECONOMY §10 (33 privileges, `built` marks the ones the app acts on); `PrivilegeGrant` by source (`base` = everyone, `item:<code>` = owning an item; Royal/VIP/events plug in later with rank-ordered inheritance and revokes); `UserPrivilegeOverride` (admin allow/deny with reason and end date; deny wins); `GET /api/me/entitlements/`, push `entitlements_updated`. Enforced now: `game_exp_bonus` and `higher_exp_limit` on game XP, and items with `requires_privilege` (e.g. `royal_items`) can't be worn without it. App: `core/entitlements/` (`entitlementsProvider` with `has`/`value`), "Your privileges" on the Profile (unbuilt ones say Soon), locked items in Customise

## Phase 3 — Ludo engine complete

- [ ] Team mode 2 v 2 (partners opposite, no friendly captures, team victory)
- [ ] Blocks as a rule option
- [ ] Variants framework: parameters + board features + modifier hooks + per-player views (PLATFORM §4)
- [ ] Variants: Quick, Snakes, Lucky, Jungle, Night, Fight (one at a time)
- [ ] Game history and replay viewer (from the action log)

## Phase 4 — Multiplayer at scale

- [ ] Matchmaking: Quick, Casual, Ranked queue infrastructure, Team/party (PLATFORM §6)
- [ ] Spectators
- [ ] Redis live game store with version-checked writes
- [ ] Multiplayer test suite: simultaneous actions, invalid requests, latency
- [ ] Load tests: 100 → 1,000 games, 10,000 connections

## Phase 5 — Social

- [ ] Friends, follow, block, mute, report, search, recently played, presence (**S1**)
- [ ] Chat: private, group, game, team, global — with moderation basics
- [ ] Social feed: posts, images, reactions, comments, feeds, moderation
- [ ] Notifications: in-app inbox + push + preferences
- [ ] Majlis rooms: rooms, members, chat, presence, mic seats without audio (**S9–S13**; gifting comes in Phase 7)
- [ ] Moments (**S14**)
- [ ] Communities / groups

## Phase 6 — Competition

- [ ] Ratings per game type (OpenSkill recommended) + ranked queue
- [ ] Leagues and seasons (Bronze → Grand Master, config)
- [ ] Leaderboards: global, weekly, monthly, friends, season + ranking history
- [ ] Tournaments: knockout → double elimination → round robin → team → seasonal

## Phase 7 — Economy

- [ ] Shop (in-game currency): skins, frames, stickers, themes, bundles, offers, discounts
- [ ] Gift catalog, sending, gifts on profiles, gift animations (**S5, S7, S8**)
- [ ] Majlis room gifting + contribution / attraction rankings + room levels + room events (**S13 gifting, S15–S18**)
- [ ] Real-money store: catalog, verified purchases, promotions, purchase history (**M1–M4**)
- [ ] Transaction history screens

## Phase 8 — Events

- [ ] Missions: daily, weekly, seasonal (progress engine)
- [ ] Events engine: event currency, event shop, event leaderboard, special modes, countdowns
- [ ] Reward Tower (one tower system for events and Royal)
- [ ] Daily Gift Commission (**M14**)
- [ ] Seasonal content

## Phase 9 — VIP and collections

- [ ] VIP subscriptions + daily rewards (**M5–M6**)
- [ ] Royal EXP, levels, privileges, Royal screen, Royal tower, VIP/Royal integration (**M7–M10**)
- [ ] Collections: albums, cards, duplicates → fragments, completion rewards, showcase
- [ ] Cosmetics expansion: vehicles, entry and victory effects, ID styles, pin-on-top, chat effects; limited items; profile customisation
- [ ] Magic cards and props, fragment exchange, Super Value Surprise (**M11–M13**)
- [ ] Visitor history, chat privileges, support priority (**M15–M17**)

## Phase 10 — Admin

- [ ] Web admin dashboard: players, games, economy, events, tournaments, social, content (PLATFORM §14)
- [ ] Full moderation and audit (**S19**), live-ops tools (**S20**), economy dashboard (**M18**)
- [ ] Analytics dashboards

## Phase 11 — Polish

- [ ] Animations, sound, haptics, performance
- [ ] Accessibility, localisation (Arabic, Urdu, Punjabi)
- [ ] Error handling review, security hardening
- [ ] Voice in Majlis rooms (WebRTC SFU)

## Phase 12 — Production

- [ ] Docker images, CI/CD deploy (staging → approval → production)
- [ ] Monitoring, logging, alerts, crash reporting
- [ ] Backups with tested restores, scaling

## Phase 13 — New games

- [ ] Domino, then Jackaroo, on the platform layer

---

## Open decisions

Answer when the phase that needs them starts.

| Decision | Needed by | Default if unanswered |
|---|---|---|
| Purchase service vs own store verification | Phase 7 store | Service for subscriptions |
| Super Value Surprise free-only | Phase 9 | Free-only |
| Reward-day reset time | 1.8 daily reward | 00:00 Bahrain time |
| Rating system | Phase 6 | OpenSkill |
| Bots in casual matchmaking | Phase 4 | Yes, labelled |
| Variant names | Phase 3 | Keep prompt names |
| Gift cash-out | Phase 7 | No |
| Voice in Majlis rooms v1 | Phase 5 | Seats without audio |
| Minimum age, spending limits | Phase 7 store | — (ask) |
| Magic cards in ranked | Phase 9 | Never |
| Punjabi script | Phase 11 | — (ask) |
| Web as a target | 1.4 | Secondary (testing), focus Android + iOS |
| Email provider for password codes (SMTP) | Before launch (Phase 12) | — (ask); development prints emails in the server terminal |
| Profile photos: image storage service + moderation | When photo avatars are built | Built-in avatars only until then |
| Board picture: `majlis_board.svg` was made from a stock file (Vecteezy); check its licence or draw our own board | Design pass (before launch) | Replace with an original board drawn in code |

Decided: real money yes — the two currencies and VIP are sold via App Store / Google Play.
Decided: the currencies are **Gold** (everyday) and **Diamonds** (premium).
