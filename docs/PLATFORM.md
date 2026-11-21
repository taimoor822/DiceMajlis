# Dice Majlis — Game Platform, Competition, Progression & Social

> Status: design. Added 2026-11-15 from the **master development prompt**.
> The single build order for everything is [planning.md](planning.md).

**Contents**

1. [How the plans fit together](#1-how-the-plans-fit-together)
2. [Product map and navigation](#2-product-map-and-navigation)
3. [A platform for many games](#3-a-platform-for-many-games)
4. [Ludo rules, variants and team mode](#4-ludo-rules-variants-and-team-mode)
5. [Rooms and match lifecycle](#5-rooms-and-match-lifecycle)
6. [Matchmaking](#6-matchmaking)
7. [Levels, ratings, leagues and leaderboards](#7-levels-ratings-leagues-and-leaderboards)
8. [Tournaments](#8-tournaments)
9. [Missions, events, collections](#9-missions-events-collections)
10. [Shop and store](#10-shop-and-store)
11. [Social: friends, feed, chat, communities](#11-social-friends-feed-chat-communities)
12. [Notifications](#12-notifications)
13. [Real-time channels and event names](#13-real-time-channels-and-event-names)
14. [Admin dashboard](#14-admin-dashboard)
15. [Analytics and privacy](#15-analytics-and-privacy)
16. [Production](#16-production)
17. [Database entities](#17-database-entities)
18. [Decisions needed](#18-decisions-needed)

---

## 1. How the plans fit together

Four prompts, one plan. Each design doc owns a part; **planning.md owns the order**.

| Doc | Covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stack, system design, rules engine, WebSocket protocol, auth, dev setup |
| **PLATFORM.md** (this) | Multi-game platform, variants, rooms, matchmaking, ratings, tournaments, missions, events, collections, shop, feed, chat types, notifications, admin, production |
| [SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md) | Profiles, Majlis social rooms, wallet ledger, gifts, rankings, moderation |
| [ROYAL_VIP_ECONOMY.md](ROYAL_VIP_ECONOMY.md) | Real-money store, VIP, Royal levels, items, reward and entitlement engines |

The master prompt sets the **phase order** (foundation → player → Ludo → multiplayer →
social → competition → economy → events → VIP & collections → admin → polish →
production) and the **first priority**: a minimum complete playable foundation before
any advanced system. Work already done fits into that order; nothing is thrown away.

Where the prompts overlap, they're merged, not duplicated:

| Topic | Decision |
|---|---|
| Currency names | Prompts say both "Gold/Diamonds" and "Coins/Gems". Names are display config over the same wallet ledger; **one pair must be chosen** (§18) |
| Reward Tower | One tower system; Royal floors and event floors are configs of it |
| Achievements, missions, collections | One progress engine (metrics + thresholds, SOCIAL_MAJLIS §11) |
| Cosmetics, collectibles, gifts, props | One item system (ROYAL_VIP_ECONOMY §4) |
| Rewards | One `grant()` engine (ROYAL_VIP_ECONOMY §5) |
| VIP checks | One entitlement engine (ROYAL_VIP_ECONOMY §9) |

---

## 2. Product map and navigation

### Primary navigation (always visible)

| Tab | What's there |
|---|---|
| **Events** | Live and upcoming events, missions, reward tower, countdowns |
| **Game Hub** | Every game and mode: Classic Ludo, 2P, 4P, team, private rooms, local play, tournaments, special and limited modes, future games |
| **Battle** | Fast competitive entry: Quick Match, Ranked, Team Battle, Private Battle, Tournament Battle |
| **Chat** | Conversations (private, group), unread counts, friends, Majlis rooms |
| **Social** | Feed, discover players, friends, following/followers, recently played, communities |

**Home** sits above the tabs (the app opens there): avatar, name, level/XP, coins and
gems, league and rank, featured content, announcements, shortcuts to Shop, Collection,
Rankings, VIP, Notifications, Settings. **Home is the game lobby, and the Battle tab in
the centre of the bar opens it** (decided 2026-11-20 from the owner's reference
screens): **Events · Game Hub · Battle · Chat · Social**. The lobby shows the games as a
carousel (Ludo · Jackaroo · Domino) with mode tiles; tapping a mode opens a match setup
(players, rules variant, entry). Design: the "Dice Majlis — Home design" canvas.

### Routing

- GoRouter with a `StatefulShellRoute` for the five tabs (each keeps its own stack);
  Battle (centre) is the Home lobby at `/home`. Built in step 1.5.
- **Guarded routes:** signed-out users go to login; VIP-only screens check entitlements;
  routes for unfinished features show a clear "coming soon" page, never fake content.
- Deep links (`dicemajlis://room/ABCD`, `/profile/123456789`, `/tournament/…`) for
  invites and notifications.

```
/splash → /login | /home
/home   (+ /shop /collection /rankings /vip /notifications /settings /profile/:playerId)
/events · /hub · /home (Battle) · /chat · /social  ← the five tabs
/hub/ludo/:mode · /room/:code · /game/:gameId · /local
```

---

## 3. A platform for many games

Ludo is the first game, not the only one. Domino and Jackaroo (and later card or
mini-games) must plug in without rewriting rooms, matchmaking, chat, economy or
profiles.

### The game interface

Every game engine is a pure module (like `ludo_engine` today) with an adapter of the
same shape. ✅ Built in step 1.10 as `backend/core/game_platform/contract.py`:

```python
class GameEngine(Protocol):
    game_type: str                                   # "ludo", "domino", "jackaroo"
    default_variant: str
    variants: Mapping[str, Variant]                  # presets of the rules, as data
    rule_error: type[Exception]                      # refused actions raise it with a `code`
    def new_game(game_id, player_ids, *, variant, seats=None, first_player_id=None) -> State
    def rules_for(variant) -> dict                   # full rules (for the catalog)
    def load(data) -> State / dump(state) -> dict    # stored snapshots
    def info(state) -> TurnInfo                      # version, finished, current player, turn,
                                                     # turn timer, winner, active players
    def prepare_action(state, action, random) -> dict  # the server's part: dice, a bot's
                                                     # choice, an idle player's auto-move
    def apply_action(state, action) -> Transition    # validates, never trusts the client
    def legal_actions(state, player_id) -> list
    def bot_action(state) -> action
    def view_for(state, player_id) -> dict           # hides private info (domino hands)
    def standings(state) -> list                     # for ratings and rewards
    def replay(initial, actions) -> State
```

All randomness comes in through `random` (`SecureRandom` on the server,
`ScriptedRandom` in tests), so every game replays exactly from its action log.

`view_for` matters for hidden-information games: in Domino each player must only
receive their own tiles, so the server never sends the whole state to everyone.

### What's shared vs per game

| Shared platform (built once) | Per game |
|---|---|
| Accounts, profiles, wallet, items, rewards, entitlements | Engine (rules, actions, bot) |
| Rooms, ready system, invites, spectators, rematch | Rules presets and variants |
| Matchmaking queues, ratings, leagues, tournaments | Board/table UI and animations |
| Game session service: locking, versioning, action log, turn timer, reconnection | Skins (board, dice, domino tiles, cards) |
| Chat, notifications, analytics | Per-game statistics |

### Changes to the existing backend (step 1.10) ✅

- `Room` and `Game` store `game_type` and `variant` (defaults `ludo` / `classic`);
  create-room takes them (checked against the registry: `unknown_game`,
  `unknown_variant`), and the variant decides the room sizes.
- `game/services.py` keeps the same locking, version check, action log and broadcast,
  but looks up the engine from the **registry** (`game_platform.get_game`) by
  `game_type`. Bots send `{"type": "bot"}` and the turn timer `{"type": "timeout"}`;
  the engine's `prepare_action` decides what that means for its game.
- What a game needs on top lives in its **table** (`game/tables/`): Ludo's are the
  Token rows and the socket messages today's app understands. A game without a table
  sends its engine events as they are.
- `GET /api/game/catalog/` lists every game, its variants and their rules.
- Ratings, leaderboards and statistics will be keyed by game type (a Ludo rating is
  not a Domino rating) when they are built.
- The Flutter side has the matching registry (`features/games/`): `game_type` →
  `GameModule` (names, icon, online board, offline route). Game Hub shows the
  catalog's games the app has a module for; a game the app is too old for gets an
  honest "update the app" page.
- The roll and move REST endpoints are Ludo's (`wrong_game` for other rooms); other
  games' actions go over the socket from step 1.12.

Adding Domino later = engine package + adapter + `register(...)` + (if needed) a
table + its app module and board. Nothing else changes.

---

## 4. Ludo rules, variants and team mode

### GameRules = parameters + board features + modifiers

The existing `Rules` object (ARCHITECTURE §6) already holds the parameters: entry
rolls, extra turns, three-sixes limit, captures, safe squares, timers, end mode,
tokens per player. Variants need two more layers:

| Layer | What | Example |
|---|---|---|
| **Parameters** | Numbers and switches | 2 tokens instead of 4, 15 s turns, no captures |
| **Board features** | Special squares placed on the track | Snake heads/tails, lucky squares, portals |
| **Modifiers** | Small rule plug-ins with fixed hooks (`on_roll`, `before_move`, `on_land`, `on_capture`, `on_turn_end`) | "Landing on a lucky square grants a power-up" |

A variant is **data**: a preset of parameters + board features + a list of modifier
codes. The engine stays deterministic: any randomness a modifier needs (a lucky draw)
is rolled by the server and passed in, exactly like the dice.

### Starting variants (rules to be refined in play-testing)

| Variant | Idea |
|---|---|
| **Classic** | Today's rules |
| **Quick** | 2 tokens each, shorter turns — fast games |
| **Jungle** | Themed board with a few obstacle squares (lose a turn / move back) |
| **Lucky** | Lucky squares give one-time power-ups (re-roll, shield, +2) from a server-rolled table |
| **Night** | Only squares near your tokens are visible; the server sends each player a filtered view (uses `view_for`) |
| **Fight** | Tokens have simple abilities with cooldowns (shield, dash) |
| **Snakes** | Snake squares slide tokens back, ladders jump them forward |

Variants appear in Game Hub as cards. **Ranked play uses Classic** (and later any
variant marked `ranked_allowed`); power-ups from purchases never exist (no pay-to-win).

### Team mode (2 v 2)

- Partners sit opposite (seats 0+2 vs 1+3).
- Partners can't capture each other; safe squares apply as normal.
- The team wins when **both** partners bring all tokens home; optional house rule:
  a finished player keeps rolling to help their partner.
- Team chat channel during the game.
- Engine change: `PlayerState.team` + team-aware capture and victory; standings by team.

### Still to add to the engine

Team mode, blocks (two same-colour tokens blocking a square, as a parameter),
modifier hooks, board features, `view_for`, game history export.

---

## 5. Rooms and match lifecycle

### Room states

```
WAITING ──all seats ready──► READY ──host starts──► STARTING (3-2-1)
   ▲  │                        │                         │
   │  └──── someone unreadies ─┘                         ▼
   │                                                 PLAYING ──game over──► FINISHED
   │                                                                          │
   └──────────────────────── rematch (same players) ◄────────────────────────┤
                                                                              ▼
                                                          CLOSED (everyone left / timeout)
```

- **Host controls:** set mode and custom rules (from allowed presets), kick before
  start, lock the room, transfer host, start when everyone is ready.
- **Player slots:** seat choice (colour), bot fill for empty seats in casual rooms
  only, ready toggle.
- **Invites:** by room code, deep link, Player ID, or the friends list.
- **Spectators** (if the room allows): read-only view, own chat channel, no hidden info.
- **Rematch:** after FINISHED, players vote; when everyone agrees a new game starts in
  the same room with the same seats.
- **Leave:** before start = free the seat; during a game = forfeit (engine already
  supports it).
- Room state lives in Postgres, live presence in Redis; every change is broadcast on
  `room/{id}`.

### What step 1.13 built ✅ (`game/rooms.py`)

Decisions made while building the lifecycle above:

- **Ready:** guests tap Ready; the host always is. READY = every guest ready, so a
  host alone may start and the Majlis AI joins (casual private rooms only). A new
  guest, a guest taking Ready back, or a rules change makes the room WAITING again;
  taking Ready back during the countdown stops it.
- **Start:** the host's start begins a 3-second countdown (STARTING,
  `GAME_START_COUNTDOWN_SECONDS`); the turn-timer sweep starts the game when it runs
  out. Nobody joins during the countdown (`game_starting`).
- **Host controls:** remove (the account can't come back unless the host invites it
  again), lock (invited players only), pass the host role (any time before CLOSED),
  custom rules (WAITING/READY only).
- **Custom rules** are each variant's `options` (`RoomOption`: key, default,
  choices); Ludo offers turn time 15/30/60 s, captures on/off, extra turn on a six
  on/off and "play on" (the game goes on until every place is decided). The engine
  gets them through `new_game(options=…)`. Any change makes the room unranked when
  ranked rooms exist (Phase 6).
- **Invites:** by 9-digit Player ID (`RoomInvite`): the friend hears `room_invite` on
  `user/<id>` and Home lists pending ones (`GET /api/game/invites/`). An invite lets
  them into a locked room and is used up when they join; invites to rooms that
  started disappear. In a locked room only the host invites. Deep links wait for a
  web domain.
- **Rematch:** after FINISHED, everyone still in the room (not left) says yes → a
  **new room** with the same people and colours (and the same bots) starts its
  countdown; the old room becomes CLOSED with `next_room`, and `rematch_started`
  `{room_code, room_id, seats: {old seat → new seat}}` tells everyone where to go.
  A new room keeps each game's history apart (one game per room). Leaving a finished
  room means not waiting for you; when nobody is left it closes.
- **Leave:** before the start the seat is freed (an empty room that never started is
  deleted); after it the seat is kept with `has_left` (a forfeit during the game).
- Messages on `room/<id>`: `players_updated` (with `is_ready`, `wants_rematch`,
  `has_left`), `room_updated` (`status, is_locked, variant, options, option_choices,
  host_id, starts_in, next_room`), `player_kicked`, `game_started`, `rematch_started`.

### Disconnect and reconnect

1. Socket drops → server marks the player `disconnected`, broadcasts
   `player_disconnected`, **keeps the seat**.
2. Their turn timer keeps running; missed turns are auto-played (already built) and
   three in a row forfeit.
3. On return: authenticate → server tells the app its active game → `sync` from the
   last version → `state_delta` or `state_snapshot` → `player_reconnected` broadcast.
4. A server restart loses nothing: the game state is in the database (and is rebuilt
   from the action log if needed).

---

## 6. Matchmaking

| Queue | Who meets | Rated |
|---|---|---|
| Quick Match | Anyone in the same mode, nearest skill available | No |
| Casual | Same as quick, can fill with bots after a wait (bots clearly shown) | No |
| Ranked | Similar rating and league; never bots | Yes |
| Team | Parties of 2 vs parties or two solos | Yes/No by mode |

How it works:

- Queues per `(game_type, mode, region)` in Redis sorted sets (by join time, with
  rating stored per entry).
- A matcher job every second takes the oldest ticket and looks for players within a
  **rating window that widens with waiting time** (e.g. ±50, +25 every 5 s, capped).
- Parties stay together; a team match needs two parties or a party plus two solos.
- When a match is found: create the room → seat players → `match_found` → STARTING.
  Anyone who doesn't accept in 10 s goes back to the queue, the others keep priority.
- Region uses the server region nearest the player (one region at first).
- Dodging or leaving ranked games gives a short queue cooldown.

---

## 7. Levels, ratings, leagues and leaderboards

| | Measures | Changes with |
|---|---|---|
| **Account level / XP** | Activity | Games played, missions, events (bonus XP from VIP/Royal allowed — it isn't skill) |
| **Rating** | Skill, per game type | Ranked results only |
| **League** | Rating band for display | Rating, per season |

### Rating

Ludo has 2–4 players and teams, so plain chess Elo doesn't fit. Recommended:
**OpenSkill** (open-source, MIT-licensed, Bayesian rating like TrueSkill) — it handles
free-for-all and teams and gives each player a skill and an uncertainty. Shown to
players as a single number. Inputs come from the engine's final standings.

### Leagues (config table)

Bronze → Silver → Gold → Platinum → Diamond → Master → Grand Master, each with
divisions, rating range, icon and season rewards. Seasons reset softly (pull ratings
toward the middle). Admin-configurable.

### Leaderboards

Global, weekly, monthly, friends, tournament and per season, per game type. Redis
sorted sets for the live boards, Postgres snapshots at period end (for history and
rewards). Ranking history per player: daily snapshot of rating and position.

Statistics tracked per player and game type: games, wins, losses, win rate, rating,
current and best streak, plus game-specific numbers (captures, perfect games).

**Anti-boosting:** win-trading detection (same players repeatedly, quick forfeits),
rating gains reduced for repeated matches between the same accounts.

---

## 8. Tournaments

- **Formats:** knockout first, then double elimination, round robin, team, seasonal.
- **Lifecycle:** scheduled → registration open → check-in → running → finished →
  rewards paid.
- **Entry rules:** level, league, VIP, entry fee in coins (from the wallet ledger,
  refunded if the tournament is cancelled), max players.
- **Brackets:** generated by seeding (rating) when registration closes; Ludo tables
  of 4 where the top 1–2 advance, or 1 v 1 for 2-player formats.
- **Match timers:** each round has a start window; no-shows lose by forfeit.
- **Automatic advancement** from game results; tournament leaderboard live on
  `tournament/{id}`.
- **Prizes** through `grant()` with key `tournament:{id}:{user}`, paid once.
- Admin creates and monitors tournaments from config; no code per tournament.

---

## 9. Missions, events, collections

### Missions and daily tasks

One progress engine: a **metric** (games played, wins, captures, friend games,
tournaments completed, XP earned, gifts sent…), a **threshold**, a **period**
(daily, weekly, season, event, permanent = achievement) and a **reward bundle**.
Metrics come from domain events (`game_finished`, `token_captured`, …), so new missions
are config, not code. Resets follow the server's reward-day boundary.

### Events engine

`Event`: start and end, visibility rules, game mode (optional special mode), missions,
event currency, event shop, leaderboard, rewards. Types: daily, weekly, monthly,
seasonal, limited-time, challenge, tournament event. Countdown and progress from the
server. **Event currency** = an extra wallet currency that expires with the event
(earned-only, never purchased, so expiry is allowed).

### Reward Tower

One tower system: floors with requirements (event points, Royal EXP, mission
progress) and reward bundles. Royal tower and event towers are configurations of it.

### Collections

- **Albums** contain **cards** (collectible items); albums can be seasonal or limited.
- Cards come from rewards, events, missions and chests.
- **Duplicates** are detected on grant and converted to fragments (exchange currency).
- Completion percentage per album; completing an album or a set pays a reward.
- **Showcase:** players pick cards or albums to show on their profile.
- Built on the item system (card = item type `collectible`).

---

## 10. Shop and store

| | **Shop** | **Store** |
|---|---|---|
| Pays with | Coins / gems (in-game currency) | Real money (App Store / Google Play) |
| Sells | Dice and board skins, avatars, frames, stickers, themes, profile cards, entry effects, vehicles, bundles, limited items | Currency packages, VIP |
| Prices | Server config (fully editable) | Store price tiers (ROYAL_VIP_ECONOMY §6) |
| Offers | Featured, daily, weekly, seasonal, limited, discounts, bundles | Bonuses, first purchase, limited packages |

A shop purchase is one transaction: price from the server catalog → wallet debit →
item grant → both ledger rows. Bundles are reward bundles with a price. Daily and
weekly offers can be personalised later; rotation is server-side.

### Customisation slots

Avatar · avatar frame · Ludo skin · dice skin · board skin · Domino skin · Jackaroo
skin · sticker packs · profile card · ornament · unique-ID style · theme · pin-on-top
decoration · vehicle · entry effect · victory effect · chat effect. Rule: **owned item
→ equip → active**, one active item per slot (a few slots like sticker packs allow
several, by design).

---

## 11. Social: friends, feed, chat, communities

### Friends and following

Follow (one-way), friend requests (accept/reject/remove), block, **mute** (hide
without blocking), report, search by Player ID or name, recently played (from game
history), online status with privacy setting. Details in SOCIAL_MAJLIS §4.

### Social feed

- **Posts:** text, images (with caption), later short clips. Images are resized and
  stored on object storage, checked by moderation before going public.
- **Reactions** (a small set of emoji) and **comments** (one level of replies).
- **Feeds:** Following, Friends, Trending (engagement in the last 24–48 h with decay),
  and each player's profile feed.
- **Moderation:** report, delete own post, hide a post, block author, admin queue;
  keyword filter; new accounts rate-limited.
- MVP builds feeds by query ("posts from people I follow, newest first", paginated);
  precomputed feeds only when traffic needs it.

### Chat

| Type | Members | Notes |
|---|---|---|
| Private | 2 people | Unread counts, typing, read receipts |
| Group | Up to N friends | Owner can add/remove |
| Game | Players in a game | Ends with the game |
| Team | Partners in a team game | Hidden from opponents |
| Global | Everyone in a language channel | Slow mode, strong moderation |
| Majlis room | Room members | SOCIAL_MAJLIS §9 |

Messages are stored per conversation with cursor paging; unread state is one
`last_read_message` pointer per member. Block and mute apply across all types.

### Communities / groups (later)

Player-created groups with a feed, chat and member roles. Builds on group chat and the
feed; comes after both are stable.

---

## 12. Notifications

- **In-app inbox** (`Notification` rows: type, payload, read) + **push** through
  Firebase Cloud Messaging (Android and iOS via APNs).
- Categories: friend requests, game invites, tournament start, event start, rewards,
  daily tasks, VIP status, messages, friend activity, system announcements.
- **Preferences** per category (push on/off, in-app always), quiet hours, and
  batching (one "3 friends are online" instead of three pushes).
- Notifications are created by domain-event handlers, never directly by features.

---

## 13. Real-time channels and event names

The prompt's channels map onto the single `/ws/v1/` connection (ARCHITECTURE §7) as
**subscriptions**, so a phone keeps one socket:

| Channel | Who can subscribe |
|---|---|
| `game/{gameId}` | Seated players (and spectators if allowed) |
| `room/{roomId}` | Room members |
| `chat/{conversationId}` | Conversation members |
| `user/{userId}` | That user only (wallet, inventory, entitlements, invites) |
| `notifications/{userId}` | That user only |
| `tournament/{id}`, `event/{id}` | Participants / anyone (read-only) |

Event names stay `snake_case` as already shipped; the prompt's names map 1:1:
`PLAYER_JOINED` → `player_joined`, `PLAYER_READY` → `player_ready`, `DICE_ROLLED` →
`dice_result` (sent to the app as `dice_rolled` today), `TOKEN_MOVED` →
`token_moved`, `TOKEN_CAPTURED` → `token_captured`, `TURN_CHANGED` → `turn_changed`,
`PLAYER_FINISHED` → `player_finished`, `GAME_FINISHED` → `game_finished`,
`PLAYER_DISCONNECTED` / `PLAYER_RECONNECTED` → `player_disconnected` /
`player_reconnected`.

Every subscription and event is authenticated, authorised, validated and rate-limited.

---

## 14. Admin dashboard

**Phase by phase:** Django admin covers configuration from day one (catalogs, rules,
tiers, events). A dedicated **web dashboard** (Phase 10) adds the operational views:

| Section | Views |
|---|---|
| Players | Search by ID/name, profile, statistics, transactions, devices, suspend / ban / unban, reset |
| Games | Active games, match history, game logs and replays (from the action log), disconnects, suspicious games |
| Economy | Balances, transactions, rewards, shop and store config, inflow/outflow charts |
| Events & tournaments | Create, edit, schedule, disable, monitor, pay out |
| Social | Posts, reports, moderation queue, user restrictions |
| Content | Banners, featured modes, announcements, cosmetics |
| Analytics | DAU/MAU, retention, games, modes, purchases, VIP conversion |

Admin roles and permissions (Super Admin, Admin, Moderator, Support, Event Manager);
every admin action logged.

---

## 15. Analytics and privacy

Track the prompt's metrics (DAU/MAU, games played and completed, match duration,
retention, session length, mode popularity, tournament and event participation, shop
purchases, currency flow, VIP conversion, social and chat activity) from **server
events and ledgers** where possible, plus a small set of app events. Collect no more
personal data than needed: no contacts, no precise location, chat content is not
analytics.

---

## 16. Production

Docker images for the backend; managed PostgreSQL and Redis; load balancer with TLS;
CI/CD from GitHub Actions (tests → build → deploy to staging → manual approval →
production); structured logs; metrics and alerts (API latency, socket count, queue
times, error rates); Sentry for crashes (app and server); nightly database backups
with tested restores; horizontal scaling of API and socket servers (ARCHITECTURE §2).

---

## 17. Database entities

How the master prompt's list maps onto the designs:

| Prompt | Where |
|---|---|
| User, Profile | `accounts.User`, `profiles.Profile` (SOCIAL_MAJLIS §3) |
| Currency, Transaction, Purchase | Wallet ledger + `Purchase` (ROYAL_VIP_ECONOMY §3, §6) |
| Inventory, Cosmetic, Collection, ShopItem | Item system (`ItemDefinition`, `InventoryItem`, …) + `Album`, `ShopOffer` |
| Achievement, Mission, Reward | Progress engine + `RewardBundle`, `RewardClaim` |
| Game, GamePlayer, Match | `Game` (+ `game_type`, `variant`), `GamePlayer`, `GameAction`; a **Match** is a matchmaking result that creates a room + game |
| Room | `GameRoom` (today's `Room`) with lifecycle states |
| Tournament, TournamentPlayer | `Tournament`, `TournamentEntry`, `TournamentMatch` |
| Event | `Event`, `EventMission`, event currency |
| Friend, Follow, Block | `Friendship`, `FriendRequest`, `Follow`, `Block`, `Mute` |
| Message, ChatRoom | `Conversation`, `ConversationMember`, `Message` |
| Post, Comment, Reaction | `Post`, `PostMedia`, `Comment`, `Reaction`, `PostReport` |
| Notification | `Notification`, `NotificationPreference`, `PushDevice` |
| VIPSubscription | `Subscription` + `VipTier` |
| League, Rating | `League`, `Season`, `PlayerRating` (per game type), `RatingHistory` |

All foreign keys indexed; unique constraints on natural keys (Player ID, room code,
`(game, version)`, idempotency keys); `(owner, created_at)` indexes on every
timeline (messages, posts, transactions, notifications).

---

## 18. Decisions needed

1. **Currency names:** "Gold & Diamonds" (economy prompt) or "Coins & Gems" (master
   prompt)? One pair everywhere.
2. **Rating system:** OpenSkill (recommended) or something else?
3. **Bots in casual matchmaking** after a wait: yes (clearly labelled) or never?
4. **Variant names:** keep Jungle / Lucky / Night / Fight / Snakes, or give them
   Majlis-themed names?
5. **Web:** the prompt says "web where practical". The app builds for web today; keep
   it as a testing/secondary target and focus on Android and iOS?
