# Dice Majlis — Profiles, Majlis Rooms & Gift Economy

> Status: design, not built yet. Added 2026-11-15.
> Extends [ARCHITECTURE.md](ARCHITECTURE.md). Progress in [planning.md](planning.md).
> Store, real-money purchases, VIP, Royal levels, items and the entitlement engine are in
> [ROYAL_VIP_ECONOMY.md](ROYAL_VIP_ECONOMY.md), which extends §3–§7 below.

**Contents**

1. [What this adds](#1-what-this-adds)
2. [What it depends on](#2-what-it-depends-on)
3. [Backend apps and tables](#3-backend-apps-and-tables)
4. [Player profile](#4-player-profile)
5. [Wallet and ledger](#5-wallet-and-ledger)
6. [Gift catalog and live-ops](#6-gift-catalog-and-live-ops)
7. [Sending a gift](#7-sending-a-gift)
8. [Gift animation engine (Flutter)](#8-gift-animation-engine-flutter)
9. [Majlis rooms](#9-majlis-rooms)
10. [Rankings and room levels](#10-rankings-and-room-levels)
11. [Achievements, moments and domain events](#11-achievements-moments-and-domain-events)
12. [Real-time events](#12-real-time-events)
13. [Safety, moderation and anti-fraud](#13-safety-moderation-and-anti-fraud)
14. [Performance](#14-performance)
15. [Flutter structure and design direction](#15-flutter-structure-and-design-direction)
16. [Testing](#16-testing)
17. [Build order](#17-build-order)
18. [Decisions needed](#18-decisions-needed)

---

## 1. What this adds

Dice Majlis becomes a place people come back to even when they aren't playing:

```
            ┌──────────── one account (Player ID) ────────────┐
            │                                                  │
   Ludo games ──► statistics ──► achievements ──► nameplates, badges
            │                         │
            │                         ▼
   Majlis rooms ──► chat ──► gifts ──► contribution / attraction rankings
            │          │        │              │
            │          │        ▼              ▼
            │          │     wallet ledger   room XP ──► room level
            │          ▼        │
            └──► moments ◄──────┘  (auto-posted from what happens)
```

Everything hangs off the **same account, wallet, social graph and event stream**.
A gift sent in a room debits the wallet, appears on the receiver's profile, moves both
rankings, adds room XP, may unlock an achievement and creates a moment — all from one
server transaction plus events (§11). Nothing is a disconnected screen.

**Original design, not a copy.** The functionality follows proven social-Ludo patterns,
but every name, asset, animation and screen is Dice Majlis' own.

> The expansion prompt mentions reference screenshots. They weren't attached, so this
> design is based on the written description.

---

## 2. What it depends on

| Needs | Why | Planned in |
|---|---|---|
| **Accounts** | Player ID, profile, wallet and friends all need a permanent user. Today a "player" exists only inside one game room | Phase 1, step 1.5 (+ Player ID) |
| **Real-time protocol v1** (`/ws/v1/`, one socket, auth, rate limits) | Rooms, presence, chat and gift broadcasts | Phase 2 |
| **Domain events** (outbox) | So games, gifts, achievements, moments and rankings stay connected without calling each other directly | Phase 2 |
| Game results per user | Real statistics | Phase 3 (game players linked to accounts) |
| Ratings and leagues | "Current/highest league" on the profile | Competitive phase — shown as "—" until then |

So the order is: **accounts → real-time v1 → identity → economy → rooms**. Building rooms
before accounts would mean throwing them away.

---

## 3. Backend apps and tables

Django apps (modular monolith, see ARCHITECTURE §4). Tables are grouped by app; all
primary keys are UUIDs, all tables have `created_at`.

| App | Tables | Notes |
|---|---|---|
| `accounts` | `User` (+ `player_id`), `DeviceSession` | `player_id`: permanent public 9-digit number, unique, indexed |
| `profiles` | `Profile`, `PlayerStatistics`, `ProfileLanguage` | 1:1 with User. Privacy settings live on `Profile` |
| `achievements` | `AchievementDefinition`, `PlayerAchievement` | Data-driven criteria (§11) |
| `cosmetics` | `CosmeticItem`, `PlayerInventory`, `EquippedCosmetic` | **One catalog for dice, nameplates, frames, badges, room backgrounds**, instead of separate Nameplate/FavoriteDice/Badge tables |
| `social` | `Follow`, `FriendRequest`, `Friendship`, `Block`, `Report` | Block overrides everything |
| `wallet` | `WalletAccount`, `WalletTransaction`, `StorePurchase` (later) | Append-only ledger (§5) |
| `gifts` | `GiftDefinition`, `GiftCategory`, `GiftTransaction`, `PlayerGiftCount` | `PlayerGiftCount` = gifts received per type, for the profile |
| `majlis` | `MajlisRoom`, `MajlisRoomLevel`, `MajlisMember`, `MajlisMessage`, `MajlisAnnouncement`, `MajlisEvent`, `MusicTrack` | Mic slots and presence live in Redis (§9) |
| `rankings` | `RankingSnapshot` (optional) | Contribution/attraction are computed from `GiftTransaction` (§10) |
| `moments` | `Moment`, `MomentReaction` | Mostly auto-generated from events |
| `moderation` | `ModerationAction`, `KeywordFilter` | Every mute/kick/ban/delete is logged |
| `events` | `DomainEvent` (outbox) | Written in the same transaction as the change |

How the prompt's model list maps here:

| Prompt | Here |
|---|---|
| PlayerProfile, PlayerStatistics | `Profile`, `PlayerStatistics` |
| Achievement, PlayerAchievement, Badge | `AchievementDefinition`, `PlayerAchievement`; badges are `CosmeticItem` type `badge` |
| Nameplate, PlayerNameplate, FavoriteDice | `CosmeticItem` (types `nameplate`, `dice`, `frame`) + `PlayerInventory` + `EquippedCosmetic` |
| PlayerGift, GiftDefinition, GiftTransaction, GiftAnimation | `PlayerGiftCount`, `GiftDefinition` (animation is a field), `GiftTransaction` |
| Wallet, WalletTransaction | `WalletAccount` (one per user per currency), `WalletTransaction` |
| MajlisRoom…Slot, Level, Announcement, Message, RoomEvent | `majlis` app; slots in Redis, levels as a config table |
| PlayerMoment, PlayerFollow, FriendRequest, Block | `Moment`, `Follow`, `FriendRequest`, `Block` |
| ContributionLeaderboard, AttractionLeaderboard | Computed from `GiftTransaction` + Redis cache, not stored tables |

**Indexes** (beyond primary keys): `User.player_id` (unique), `User.username` (unique,
case-insensitive), `GiftTransaction (room, created_at)`, `(sender, created_at)`,
`(recipient, created_at)`, unique `(sender, idempotency_key)`;
`WalletTransaction (account, created_at)`, unique `(account, idempotency_key)`;
`MajlisMessage (room, created_at)`; `MajlisMember (room, user)` unique and
`(room, last_seen_at)`; `Moment (user, created_at)`; `Follow (follower, followee)` unique.

---

## 4. Player profile

### Header

Avatar with equipped frame · display name with equipped nameplate · **Player ID** with
a Copy button · country flag · level · online status · relationship buttons · ⋯ menu.

- **Player ID:** random 9-digit number (100000000–999999999), generated with the
  secure RNG, never changes, never reused. Random, not sequential, so it doesn't reveal
  how many users exist or let anyone walk through every profile.
- **Search:** exact Player ID, or username prefix (3+ characters), rate-limited.
- **Privacy:** country, gender and online status are **optional and user-controlled**
  (gender hidden unless the player chooses to show it). Blocked users can't open each
  other's profile.
- **Level:** from account XP (games played, wins, daily activity). Separate from
  league/rating (skill).

### Buttons change with the relationship

| Relationship | Shown |
|---|---|
| Me | Edit profile · Wallet · Settings |
| Stranger | Add friend · Follow · Gift · ⋯ (Block, Report) |
| Request sent | Requested · Follow · Gift · ⋯ |
| Friend | Message · Invite to game · Gift · ⋯ (Unfriend, Block, Report) |
| Blocked by me | Unblock only |
| Blocked me | Profile not available |

### Tabs

The prompt's `PROFILE | MEMBERS | MOMENTS` mixes the **player profile** and the
**room info page**. They're split:

- **Player profile:** `Profile` (about, languages, statistics, achievements, favourite
  dice, gifts showcase) · `Moments`
- **Majlis room info:** `Room` (announcement, level, owner, admins) · `Members` · `Moments`

### Statistics (from real games only)

Stored in `PlayerStatistics`, updated by the `game_finished` event handler from the
engine's final standings — never typed in by hand.

| Shown | Source | Available |
|---|---|---|
| Total games, wins, losses, win rate | standings (1st place = win) | Phase 3 |
| Win streak, best win streak | consecutive wins | Phase 3 |
| Games this season | per-season counter | Competitive phase |
| Current/highest rating, current/highest league, season rank | ranking service | Competitive phase ("—" before) |
| Draws | **Ludo has no draws** — not shown | — |

**Bot games don't count** towards statistics, achievements or rewards. Otherwise anyone
could farm wins and coins against the bot.

### Languages

Spoken-language badges chosen by the player: English, Arabic, Urdu, Punjabi (list is
configurable). This is separate from the app's own display language (ARCHITECTURE §1).

### Achievements, favourite dice, nameplates, gifts showcase

- **Achievements:** grid of unlocked (animated glow) and locked (🔒 + `37/100` progress
  bar), with rarity frame. Details in §11.
- **Favourite dice / nameplates / frames:** cosmetics the player owns; one of each
  type can be **equipped**. Rarity: Common, Rare, Epic, Legendary, Mythic. *Limited* is
  an availability flag, not a rarity (an item can be Legendary **and** Limited).
  Nameplates and frames can be animated (Lottie/Rive asset).
- **Gifts:** totals per gift type received (🌹 × 12, 👑 × 5), newest senders, and up to
  6 gifts the player picks to showcase.

---

## 5. Wallet and ledger

### Two currencies

| | 🪙 Gold coins | 💎 Diamonds |
|---|---|---|
| Role | Everyday currency | Premium currency |
| Earned by | Daily login, games, missions, achievements, events; **purchases** (Phase 9) | Event prizes, admin grants; **purchases** (Phase 9) |
| Buys | Common gifts, some cosmetics | Premium gifts, premium cosmetics, VIP, pass |

### Rules

1. **The app never sends amounts or prices.** It sends "send gift X × 3 to Y". The
   server looks up the price, checks the balance and decides.
2. **Balances change only through `wallet.services.post()`**, which in one DB
   transaction locks the account row (`SELECT … FOR UPDATE`), checks the balance, writes
   one `WalletTransaction` row and updates the cached balance.
3. **The ledger is append-only.** Mistakes are fixed by a *reversal* entry, never by
   editing or deleting rows.
4. **Idempotency:** every entry has an `idempotency_key` (unique per account). The same
   request twice = one entry. Store purchases use the store's transaction ID, so a
   replayed receipt can't credit twice.
5. **No negative balances:** a database check constraint `balance >= 0`.
6. **Nightly audit:** for every account, the sum of its transactions must equal its
   balance. Any mismatch raises an alert.

### `WalletTransaction`

| Field | |
|---|---|
| `id` | UUID (shown to support as `TXN-…`) |
| `account` → user + currency | |
| `amount` | signed integer (−699 for a spend, +500 for a reward) |
| `type` | `gift_send`, `reward_daily`, `reward_achievement`, `reward_event`, `game_reward`, `admin_grant`, `admin_revoke`, `purchase`, `reversal` |
| `reference_type`, `reference_id` | e.g. `gift_transaction` + its ID |
| `balance_after` | for support and audits |
| `idempotency_key` | unique per account |
| `metadata` | JSON (recipient, room, admin who granted, reason) |
| `created_at` | |

### What a receiver gets

The receiver gets the **gift on their profile** and **attraction points** for the
rankings — **not currency**. Received gifts can't be cashed out or converted back. This
keeps Dice Majlis a game, not a payment service. If cash-out were ever wanted, it would
bring payment and money-transfer regulation, app-store rules and tax questions, and
would need proper legal advice before any design work. I'm not a lawyer, so treat this
as the reason to decide early, not as legal guidance.

### Real-money diamonds (Phase 9, not before)

When diamonds are sold, they must be bought through **Apple In-App Purchase and Google
Play Billing** (both stores generally require this for digital currency). The server verifies every
receipt with the store before crediting, and listens to store refund notifications.
If a refunded purchase was already spent, the balance goes to 0 and the rest is
recorded as debt that future earnings repay. Add **spend limits** and an age check for
purchases. Until Phase 9 the whole economy runs on earned and granted currency, so it
can be tested and balanced without real money.

---

## 6. Gift catalog and live-ops

Gifts are **data**, edited in the admin panel. The app downloads the catalog, so new
gifts, prices and seasonal items go live **without a new app release**.

### `GiftDefinition`

| Field | Example |
|---|---|
| `code`, `name`, `description` | `golden_lion`, "Golden Lion" |
| `category` | Classic, Popular, Royal, Premium, Seasonal, Special (tab order set in admin) |
| `currency`, `price` | diamonds, 699 |
| `value_points` | 699 — what it counts for in rankings and room XP (§10) |
| `rarity` | common · rare · epic · legendary · mythic |
| `icon`, `preview_asset`, `animation_asset`, `sound_asset` | CDN URLs, versioned |
| `animation_type`, `animation_params` | `fly_to_avatar`, `{ "duration_ms": 3500, "particles": "gold" }` |
| `targeting` | single · multiple · all_on_mic · room · host |
| `availability` | always · window (`start_at`/`end_at`) · vip · event · tournament_reward |
| `max_per_user_per_day` | optional |
| `is_active`, `sort_order` | |

**Prices live only on the server.** The app shows what the catalog says and the server
re-checks at send time, so an old cached catalog can never buy at an old price.

Starter catalog (prices are placeholders to balance later):

| Gift | Currency | Price | Rarity | Animation |
|---|---|---|---|---|
| 🎈 Balloon | 🪙 | 500 | common | small pop |
| 🌹 Rose | 🪙 | 1,000 | common | small pop |
| 🍯 Honey | 🪙 | 1,500 | common | small pop |
| 🎁 Small gift | 🪙 | 2,000 | rare | fly to avatar |
| 🦁 Golden Lion | 💎 | 699 | epic | fly to avatar + burst |
| ✨ Royal Effect | 💎 | 999 | epic | avatar aura |
| 🛳 Ocean Royal | 💎 | 4,999 | legendary | room-wide |
| 🏰 Majlis Castle | 💎 | 5,999 | legendary | full-screen scene |
| 🏮 Ramadan Lantern | 💎 | — | limited (Ramadan) | room-wide |

---

## 7. Sending a gift

```
App: send_gift {gift_code, quantity, targets[], room_id?, idempotency_key}
  │
  ▼  one database transaction
1. Same idempotency_key seen?  → return the original result (no second charge)
2. Load gift: active? in its time window? VIP/event rule met? daily limit ok?
3. Targets valid? (in the room / not blocked / not yourself)
4. total = price × quantity × number_of_targets          (server-side maths)
5. Lock sender's wallet row → balance ≥ total?  else "insufficient_balance"
6. Write WalletTransaction  (−total, type gift_send)
7. Write GiftTransaction    (sender, targets, room, quantity, total, value_points)
8. Update PlayerGiftCount for each receiver (+quantity)
9. Write DomainEvent "gift_sent"   (outbox, same transaction)
  │  commit
  ▼
10. Broadcast gift_received (+ animation info) to the room
11. Event handlers: rankings, room XP, achievements, moments, notifications
```

- Steps 1–9 either all happen or none do. A crash in the middle leaves no money missing.
- **Disconnect during a send:** the app retries with the **same** `idempotency_key`
  and gets the stored result. It never charges twice.
- **Combos** (🌹 × 10 → × 50 → × 100): each tap is a normal paid send. The server
  keeps a short-lived combo counter in Redis (same sender + gift + target, 3-second
  window) and returns `combo_count` so the animation can grow. The counter is display
  only and can't create value.
- **Reversals** (admin or fraud): one `reversal` ledger entry refunds the sender,
  rankings and gift counts are adjusted, and the original rows stay for the audit.

---

## 8. Gift animation engine (Flutter)

Animations are chosen by data, not hard-coded per gift:

```
GiftDefinition (from server)
   │ animation_type, rarity, assets, params, combo_count
   ▼
GiftAnimationRequest ──► GiftAnimationQueue (per room) ──► renderer registry
                                                            │
       small_pop · fly_to_avatar · burst · avatar_aura · rain · fireworks
       room_wide · full_screen · particle_explosion · scene (vehicle/animal/fantasy)
```

| Rarity | Default impact | Default length |
|---|---|---|
| Common | Small pop near the receiver | ~1 s |
| Rare | Flies to the receiver's avatar | ~2 s |
| Epic | Burst + aura on the receiver, room dims slightly | ~3 s |
| Legendary | Room-wide scene, screen dims, announcement banner | ~5 s |
| Mythic | Full-screen scene with sound | ~7 s |

- **Renderer registry:** a map from `animation_type` to a widget builder. A new gift
  that reuses an existing type needs **no app update**, just new assets.
- **Unknown type** (older app, newer gift): fall back to the default animation for its
  rarity. Never crash, never hide the gift.
- **Assets:** Lottie or Rive files, downloaded on first use and cached by version.
  Catalog icons are preloaded, big animations are lazy-loaded.
- **Queue:** big animations play one at a time; small ones can overlap (max 3). If the
  queue backs up, small ones are merged ("🌹 × 37") so the room stays smooth.
- **Settings:** players can turn off full-screen effects and sounds. The gift banner
  still shows.
- **Sequence for a legendary gift** (prompt example): dim → golden particles → crown
  flies to the receiver → golden light → avatar highlighted → banner
  "Taimoor sent Golden Crown to M" → fade out.

---

## 9. Majlis rooms

Persistent social rooms, separate from the short-lived Ludo game rooms.

### What lives where

| Postgres (durable) | Redis (live, can be rebuilt) |
|---|---|
| Room: public room ID, name, owner, announcement, level, XP, background, capacity, music settings | Who is online in the room (sorted set by heartbeat) |
| Members: user, role, joined_at, muted_until, banned_until | Mic slots: who sits where, muted or not, locked or not |
| Messages (history), announcements | Now playing: track + start time |
| Gift transactions, room events | Combo counters, rate limits, ranking cache |

If Redis restarts, slots empty and people re-sit. Nothing important is lost.

### Members, visitors and capacity

- **Member** = joined the room (kept). **Online** = inside right now.
- Capacity is configurable per room and grows with room level, e.g. 200 at level 1.
  "81 / 40,000" is only a display of member count against the room's own limit.
- The members list is **paginated from the server**, with search by exact Player ID or
  username prefix. Online-first sort. The full list is never pushed over the socket.

### Roles

Owner (one) · Admins · Moderators · Members · Visitors. What each can do:

| Action | Owner | Admin | Moderator | Member |
|---|---|---|---|---|
| Edit name, announcement, background, music | ✓ | ✓ | | |
| Appoint admins / moderators | ✓ | admins: ✗, mods: ✓ | | |
| Mute, kick, delete message | ✓ | ✓ | ✓ | |
| Temporary / permanent ban | ✓ | ✓ | temp only | |
| Lock / unlock mic slot, move someone off mic | ✓ | ✓ | ✓ | |
| Sit on an open slot, chat, gift | ✓ | ✓ | ✓ | ✓ |

### Mic slots (voice-ready)

Number of slots comes from the room level (e.g. 5 → 10). Each slot:

```
empty ──sit──► occupied(user, mic_off) ──mic_on──► occupied(user, mic_on)
  ▲                │        ▲                          │
  └──leave/kick────┘        └────────mic_off───────────┘
locked: nobody can sit (owner/admin/moderator)
```

Version 1 ships the **slots, states and UI with no audio**. Voice later: the server
gives an audio token to people on slots (talk) and to listeners (hear) from a WebRTC
SFU such as LiveKit (open source). Nothing in the slot design has to change. Voice with
strangers needs extra moderation (host can mute anyone on mic) and should consider age
limits.

### Room audio (music)

- Music comes from a **licensed or original track catalog** (`MusicTrack` with licence
  details). No user uploads and no streaming of unlicensed music.
- The owner or an admin picks a track. The server stores *track + start time*; every
  phone streams the file from the CDN and jumps to the same position. Volume and mute
  are per phone. Short sound effects ship with the app.

### Room chat

Text, emojis, stickers (from a catalog), system messages, gift announcements and host
announcements. Join/leave lines are shown live but **not stored** (they'd be most of
the database for little value). History loads in pages of 50, newest first.

---

## 10. Rankings and room levels

### Contribution (who gives) and attraction (who receives)

- Unit: **gift value points** (`value_points × quantity`), so coin and diamond gifts
  rank on one scale. Admins set points per gift (default: diamonds 1:1, coins ÷ 100).
- Windows: **last 24 hours** and **last 7 days**, per room and globally.
- How: Redis sorted sets in hourly buckets (`rank:contrib:{room}:{hour}`); a 24h or 7d
  board is the union of the last 24 or 168 buckets, cached for ~10 s. Postgres
  `GiftTransaction` stays the source of truth and can rebuild any board.
- Live updates: `contribution_updated` / `attraction_updated` are sent **at most every
  3 seconds per room**, with the top 10 only.

### Room level

Room XP comes from gift value points, daily active members and room events (with daily
caps so spam doesn't level a room). Levels are a **config table**, so the curve can be
tuned without code:

| Level | XP needed | Mic slots | Member cap | Unlocks |
|---|---|---|---|---|
| 1 | 0 | 5 | 200 | basic backgrounds |
| 10 | 50,000 | 8 | 1,000 | animated background |
| 25 | 400,000 | 10 | 5,000 | room gifts, events |
| 50 | 1,988,800 | 10 | 40,000 | premium effects, exclusive gifts |

(Numbers are placeholders.) Levelling up broadcasts `room_level_updated` and plays a
room effect.

### Room events

Owners and admins create events from templates: gift battle, popularity contest,
welcome event, daily/weekly challenge, seasonal. Prizes (diamonds, badge, nameplate)
are paid by the server through the ledger (`reward_event`) when the event ends, with
the event + winner as the idempotency key, so no prize is ever paid twice.

---

## 11. Achievements, moments and domain events

### Domain events keep everything connected

Important changes write a `DomainEvent` row **in the same transaction** (the outbox).
A worker (alongside the turn timer) hands each event to its handlers and marks it done.
Handlers are idempotent, so an event processed twice changes nothing twice.

*Built in step 2.1:* `backend/core/events/` (`emit(kind, payload)`, `on(kind, handler)`).
Handlers run right after the commit; one that fails is rolled back and retried by the
sweep (wait 2, 4, 8 … minutes, up to 8 tries; `last_error` shows why). `game_finished`
comes from `game/results.py` (payload documented there) and feeds account XP today.

| Event | Handlers |
|---|---|
| `game_finished` | statistics, account XP, achievements, moments (big wins) |
| `gift_sent` | gift counts, rankings, room XP, achievements, moments, notifications |
| `achievement_unlocked` | reward via ledger, moment, notification |
| `room_level_up` | room broadcast, moment |
| `friend_added`, `followed` | achievements, notifications |

### Achievements

`AchievementDefinition`: code, name, description, icon, rarity, **metric**, threshold,
optional tiers (10 / 100 / 1,000), reward (coins or a cosmetic), hidden flag.
Metrics are counters kept up to date by the handlers: `games_played`, `wins`,
`best_win_streak`, `gift_value_sent`, `friends`, `tournaments_won`,
`diamonds_collected`, and so on. Examples: 🏆 First Victory (wins ≥ 1) ·
🎯 100 Games · 🔥 10 Win Streak · 🎁 Gift Giver (gift value sent ≥ 10,000) ·
👥 Social Star (friends ≥ 50).

### Moments

Auto-posted from events (tournament win, league promotion, achievement, gift sent or
received, room activity, milestones), each with a timestamp, text, optional image or
gift preview, and reactions. Filters: All · Gifts · Honours · Activity. Players can hide
moment types they don't want shown. Player-written posts and comments come later, with
the same moderation as chat.

---

## 12. Real-time events

Added to the `/ws/v1/` protocol (ARCHITECTURE §7: auth by first message, `req_id`
idempotency, rate limits, coded errors). Every client event is checked for
**authentication, permission in that room, payload shape and rate limit**, then
processed on the server.

| Client → server | Server → clients | Limit (initial) |
|---|---|---|
| `room_join {room_id}` · `room_leave` | `room_snapshot` (to joiner) · `member_joined` / `member_left` (batched) · `online_count` | 5/min |
| `send_message {text}` | `message_received` | 1/s, burst 5 |
| `sit_in_slot {slot}` · `leave_slot` · `mic_on` · `mic_off` | `slot_updated` | 2/s |
| `send_gift {gift, qty, targets, idempotency_key}` | `gift_received {…animation}` · `combo_updated` | 10/s |
| `mod_action {mute/kick/ban/delete/lock}` | `member_muted` · `member_kicked` · `message_deleted` · `slot_updated` | 5/s |
| — | `contribution_updated` · `attraction_updated` (≤ 1 per 3 s) | |
| — | `room_level_updated` · `announcement_created` · `music_changed` | |
| — | `moment_created` (to followers, batched) | |

`gift_animation_start` / `gift_animation_end` from the prompt stay **inside the app**:
the server sends one `gift_received` and each phone plays it locally. Echoing animation
timing through the server would double the traffic for nothing.

**`room_snapshot`** (on join) holds: room info, online count, top-of-list online
members, mic slots, now playing, last 50 messages, top 3 contributors. After that, only
changes are sent.

---

## 13. Safety, moderation and anti-fraud

### Ships together with chat (not at the end)

Public chat with strangers needs these **from day one**. App stores also expect
apps with user-generated content to have filtering, reporting and blocking:

- Keyword filter (configurable list, Arabic/English/Urdu)
- Report a message, user or room → admin queue
- Block a user (hides their messages and gifts for you; they can't message you)
- Room roles with mute, kick, delete, temporary ban
- Every moderation action logged (`ModerationAction`)

Later: permanent bans, appeal flow, shared ban lists, automatic flags.

### Economy protection

| Threat | Defence |
|---|---|
| Double-tap / replayed request | `idempotency_key` unique per sender |
| Edited app sending prices or balances | Server ignores them; prices and balances come only from the database |
| Two gifts at once overspending | Row lock on the wallet + `balance >= 0` constraint |
| Fake gift events | Only the server broadcasts gifts, after commit |
| Rapid spam | Rate limits per user and per room |
| Farming with alt accounts (bot games, gifting between own accounts) | Bot games give no rewards; new accounts have daily send limits; flags for gifts between accounts sharing a device; admin review |
| Ledger drift | Nightly balance audit with alerts |
| Abuse found later | Reversal entries, account freeze |

Spending limits and an age check apply before any real-money purchase (Phase 9).

---

## 14. Performance

- **Never send the whole room for small changes:** one snapshot on join, then deltas.
- **Batch noisy events:** joins/leaves and presence counts every 1–2 s; ranking
  updates at most every 3 s.
- **Paginate everything:** members, messages, moments, gift history, transactions
  (cursor-based).
- **Flutter:** `ListView.builder` (virtualised) for chat and members, cached images,
  lazy-loaded animation assets, a cap on simultaneous animations.
- **Redis** for hot data (presence, slots, rankings); Postgres for history.
- **Large rooms:** above ~1,000 online, show "1.2k online" and hide individual
  join/leave lines.

---

## 15. Flutter structure and design direction

Builds on ARCHITECTURE §3 (`core/ shared/ features/`). Every feature has
`data/ domain/ presentation/`.

```
features/
├── profile/          # my profile + other players' profiles (one feature, two modes)
│   ├── achievements/ · favorite_dice/ · nameplates/ · gift_showcase/
├── social/           # follow, friends, requests, block, report, player search
├── wallet/           # balances, transaction history
├── gifts/            # catalog, gift panel, send flow
│   └── animation/    # GiftAnimationQueue, renderer registry, renderers
├── majlis_room/      # room screen, room info
│   ├── members/ · chat/ · voice/ (mic slots) · music/ · rankings/ (contribution, attraction)
└── moments/
```

The prompt's separate folders (`player_profile`, `room_members`, `room_chat`,
`room_voice`, `contribution`, `attraction`) are kept as sub-folders so related code
stays together.

### Design direction

Two moods, one identity:

| | Profile screens | Majlis room |
|---|---|---|
| Feel | Bright, premium, decorative | Dark, immersive, glowing |
| Base | Ivory / sand with teal accents | Deep navy-teal |
| Accents | Gold, emerald | Gold, turquoise glow, glass panels |
| Texture | Light Arabic geometric patterns | Lantern light, soft geometric overlay |

Theme tokens (in `core/theme`, step 1.4), starting values to refine:

| Token | Colour |
|---|---|
| `navy` | `#0B1F2E` |
| `teal` | `#0E4D57` |
| `turquoise` | `#2EC4B6` |
| `emerald` | `#1F8A64` |
| `gold` | `#D4A84B` |
| `sand` | `#F4EBDD` |
| Rarity: common · rare · epic · legendary · mythic | `#9AA5B1` · `#3BA7E0` · `#9B5DE5` · `#E8B33C` · `#E0475F` → gradient |

Animations explain an action (gift sent, level up, badge unlocked). Players can turn
heavy effects off, and performance always wins over effects.

---

## 16. Testing

| Area | Must be tested |
|---|---|
| Profile | Loading own vs other profile, privacy settings, Player ID search, relationship buttons for every state |
| Statistics | Updated from real game results; bot games ignored; win streaks |
| Achievements | Unlock at threshold, tiers, reward paid exactly once |
| Wallet | Grants, spends, reversal, `balance >= 0`, nightly audit finds a planted mismatch |
| Gifts | Coin gift, diamond gift, insufficient balance, duplicate `idempotency_key`, **two sends at the same time from one wallet**, disconnect then retry, expired limited gift, VIP-only gift, blocked recipient, multi-target pricing |
| Rooms | Join/leave, snapshot, member search, chat paging, presence counts, slot state machine, role permissions |
| Moderation | Mute/kick/ban/delete, keyword filter, report queue, block hides messages |
| Rankings | 24h/7d windows, rebuild from Postgres matches Redis |
| Flutter | Animation queue order and merging, unknown animation type fallback, gift panel shows server prices |
| Load | 1,000 users in one room, 100 gifts/second across rooms (before claiming scale) |

---

## 17. Build order

> **When** each step is built is decided by the master roadmap in
> [planning.md](planning.md) (S-codes are spread across phases 2, 5, 7 and 10). This
> section describes each step and its "done when".

The prompt's 20 steps, kept in order where possible and grouped into phases. Two
changes: **basic moderation moves next to chat** (safety and store rules), and **real
money comes last**. Every step ships something usable and keeps the app working.

**Before any of this:** Phase 1 accounts (1.5) gains the permanent Player ID, and
Phase 2 delivers `/ws/v1/`, presence and the domain-event outbox.

### Phase 3 — Identity (prompt steps 1–4)

| Step | Build | Done when |
|---|---|---|
| S1 | Profile page: header, Player ID copy/search, languages, privacy, tabs; social graph (follow, friends, block, report) with relationship-aware buttons | Two accounts can find, friend and block each other |
| S2 | `PlayerStatistics` from real online games | Playing a game updates both players' stats |
| S3 | Achievements engine + first 15 achievements | Winning a first game unlocks First Victory exactly once |
| S4 | Item system (ROYAL_VIP_ECONOMY §4) with cosmetics first: dice, nameplates, frames — own + equip | Equipped dice shows on the profile and in game |

### Phase 4 — Economy and gifts (prompt steps 5–8)

| Step | Build | Done when |
|---|---|---|
| S5 | Gift catalog in admin + catalog API | Admin adds a gift; the app shows it without an update |
| S6 | Wallet + ledger (coins, diamonds); daily login coins; admin grants | Every balance change has a ledger row; audit passes |
| S7 | Send gift to a player's profile (atomic, idempotent); gifts on profile | All gift tests in §16 pass |
| S8 | Gift animation engine with all 5 rarity tiers + combos | Each tier plays correctly; unknown type falls back |

### Phase 5 — Majlis rooms (prompt steps 9–13)

| Step | Build | Done when |
|---|---|---|
| S9 | Create/join rooms, room screen, background, room info | Players can create a room and see each other inside |
| S10 | Members list with server search and roles | Search by Player ID works in a 10k-member test room |
| S11 | Room chat + **moderation basics** (filter, report, block, mute, kick, delete) | Owner can mute and kick; reports reach the admin queue |
| S12 | Presence and online counts | Counts stay correct through disconnects |
| S13 | Mic slots (UI + state, no audio); room gifting with targets; music from licensed catalog | Sit, change slot, mute; gift to someone on mic plays in the room |

### Phase 6 — Room social loop (prompt steps 14–20)

| Step | Build | Done when |
|---|---|---|
| S14 | Moments (auto-posted) | Gifts and achievements appear as moments |
| S15 | Contribution ranking (24h, 7d) | Matches a rebuild from Postgres |
| S16 | Attraction ranking | Same |
| S17 | Room levels, XP, unlocks | Levelling up adds mic slots and plays the effect |
| S18 | Room events (gift battle) with prizes via ledger | Prize paid once, even if the job runs twice |
| S19 | Full moderation: admin/moderator roles, permanent bans, audit view | Every action visible in the audit log |
| S20 | Live-ops admin: schedule gifts, events, banners | A limited gift appears and disappears on its dates |

Then: **Competitive** (ratings, leagues, seasons — fills the league fields),
**Tournaments**, **Monetisation** (diamond purchases, VIP, Majlis Pass), **Voice**
(WebRTC SFU) and **Polish**.

---

## 18. Decisions needed

1. **Real money:** ✅ answered yes — gold, diamonds and VIP via App Store / Google Play
   (Phase 9, see ROYAL_VIP_ECONOMY.md).
2. **Cash-out:** can received gifts ever be turned into money? (Assumed **no**, see §5.)
3. **Voice:** is v1 without audio acceptable (slots, mute states and UI only)? (Assumed yes.)
4. **Age:** minimum age for public rooms, voice and purchases.
5. **Punjabi:** Shahmukhi or Gurmukhi script for app text, when it's translated?
