# Dice Majlis — Store, VIP, Royal Levels & Premium Items

> Status: design, not built yet. Added 2026-11-15.
> Extends [SOCIAL_MAJLIS.md](SOCIAL_MAJLIS.md) (wallet §5, gifts §6–7, cosmetics §4).
> Progress in [planning.md](planning.md).

**Contents**

1. [What this adds](#1-what-this-adds)
2. [Read first: rules that shape the design](#2-read-first-rules-that-shape-the-design)
3. [Currencies and ledgers](#3-currencies-and-ledgers)
4. [One item system](#4-one-item-system)
5. [One reward engine](#5-one-reward-engine)
6. [Store and purchases](#6-store-and-purchases)
7. [VIP subscriptions](#7-vip-subscriptions)
8. [Royal Level and Royal EXP](#8-royal-level-and-royal-exp)
9. [Entitlement engine](#9-entitlement-engine)
10. [Privilege catalog](#10-privilege-catalog)
11. [Reward Tower, fragments, surprises, gift commission](#11-reward-tower-fragments-surprises-gift-commission)
12. [Social priority and visitor history](#12-social-priority-and-visitor-history)
13. [Rooms, chat and customisation](#13-rooms-chat-and-customisation)
14. [Customer support priority](#14-customer-support-priority)
15. [Security and anti-cheat](#15-security-and-anti-cheat)
16. [Real-time updates](#16-real-time-updates)
17. [Admin, analytics and balancing](#17-admin-analytics-and-balancing)
18. [Database entities](#18-database-entities)
19. [Flutter modules and state](#19-flutter-modules-and-state)
20. [Testing](#20-testing)
21. [Build order](#21-build-order)
22. [Decisions needed](#22-decisions-needed)

---

## 1. What this adds

A premium layer on the same account, wallet and event system as the social features:

```
                    ┌──────── Store (gold, diamonds, VIP) ────────┐
                    │   App Store / Google Play → server verify   │
                    ▼                                             ▼
   Wallet ledger (gold, diamonds, fragments)          Subscriptions (VIP Knight, Baron, …)
          │            │                                          │
          │            ▼                                          │
          │      Royal EXP ledger ──► Royal Level ────────────────┤
          ▼                                                       ▼
   Item ledger (gifts, magic cards, props,         Entitlement engine: "may this user do X?"
   cosmetics, recharge tickets, chests)            used by rooms, chat, profile, lists, support
          │                                                       │
          └────────── Reward engine (daily VIP, tower, level-up, commission, events) ─┘
```

Five building blocks carry everything in the prompt: **wallet ledger, item ledger,
reward engine, Royal EXP ledger, entitlement engine.** Every screen (store, VIP,
Royal, inventory, tower, exchange) is a view over these, so nothing is a separate
mock screen and nothing needs rebuilding when a new tier, level or item is added.

---

## 2. Read first: rules that shape the design

These come from App Store / Google Play rules and from keeping the game fair. They
change a few things in the prompt. (I'm not a lawyer; the store rules are summarised
from their published guidelines and should be re-checked before launch.)

| Topic | What it means here |
|---|---|
| **Prices live in the stores** | Real-money prices are set per country in App Store Connect and Google Play Console, and the app must show the store's localised price. The admin panel controls *which* products show, amounts, bonuses, badges, order, dates and regions. To change a price: change it in the store console (no app update needed) or switch the package to another pre-created product. |
| **Purchases only through the stores** | Gold, diamonds and VIP are sold through Apple In-App Purchase and Google Play Billing. Nothing is granted because the app says "payment succeeded"; the server verifies every purchase with Apple or Google first. |
| **Purchased currency never expires** | Store rules don't allow bought currency to expire. Items *can* be time-limited (a 7-day prop), currencies can't. |
| **Random paid rewards = loot box** | If a random reward can be obtained with real money (directly or with bought diamonds), both stores require showing the odds **before** purchase, and some countries restrict or ban paid loot boxes. Gambling is illegal in Bahrain and much of the Gulf. Default here: **Super Value Surprise is free-only** (a Royal privilege), odds always shown, paid draws off until checked per country. |
| **No pay-to-win** | "Priority ranking" and "display on top" affect **social lists only** (friends, room members). They never affect ratings, leagues, competitive leaderboards or matchmaking. Magic cards that change Ludo play are **never** allowed in ranked games. |
| **Restore purchases** | Required for subscriptions: a reinstall or new phone gets VIP back. |
| **Received gifts aren't money** | Daily Gift Commission rewards are in-game items/currency, never cash (same rule as SOCIAL_MAJLIS §5). |
| **Some things ship inside the app** | Alternative **app icons** must be bundled in the app binary (iOS and Android); the server only unlocks which ones a user may pick. The native launch screen is fixed in the binary too; "exclusive launch screen" is an in-app welcome screen shown right after it, which *can* be remote. |
| **Minors** | Spending limits and an age check before purchases; voice messages and GIFs need moderation. |

---

## 3. Currencies and ledgers

| Currency | Role | Comes from | Spent on |
|---|---|---|---|
| 🪙 **Gold** | Everyday | Purchases, games, daily rewards, missions, VIP daily | Common gifts, props, exchanges |
| 💎 **Diamonds** | Premium | Purchases, VIP daily, events, tower | Premium gifts, cosmetics, items |
| 🧩 **Fragments** | Collection currency | Rewards, duplicates, events | Fragment Exchange only (§11) |

All three use the **same wallet ledger** (SOCIAL_MAJLIS §5): one `WalletAccount` per
user per currency, append-only `WalletTransaction`, row lock, `balance >= 0`
constraint, idempotency keys, nightly audit. New currencies are a new row, not new
code. The transaction gains **`balance_before`** next to `balance_after`, and a
`source` field (e.g. `purchase:diamonds_400`, `vip_daily:baron`, `gift:golden_lion`).

The prompt's package examples become **store configuration** (placeholders, all
editable in admin):

| Gold | Price | Diamonds | Price |
|---|---|---|---|
| 33,000 | $0.99 | 400 | $0.99 |
| 130,000 | $2.99 | 1,800 | $3.99 |
| 670,000 | $8.99 | 5,000 | $9.99 |
| 2,700,000 | $18.99 | 16,000 | $29.99 |
| 7,700,000 | $39.99 | 53,700 | $99.99 |
| 17,000,000 | $69.99 | 161,700 | $299.99 |

---

## 4. One item system

Gifts you own, magic cards, props, cosmetics, recharge tickets and chests are all
**items** with different types. One system means one set of rules for ownership,
expiry, history and anti-duplication.

### `ItemDefinition` (admin-managed catalog)

| Field | Example |
|---|---|
| `code`, `type` | `entrance_falcon`, `prop` |
| types | `gift` · `magic_card` · `prop` · `cosmetic` · `recharge_ticket` · `chest` |
| `subtype` | for cosmetics: `profile_frame`, `profile_skin`, `avatar_effect`, `room_theme`, `entrance_effect`, `chat_theme`, `name_style`, `badge`, `sticker_pack`, `dice`, `nameplate`, `app_icon` |
| `name`, `description`, `rarity`, assets | as in the gift catalog |
| `effect` | JSON, e.g. `{"kind": "entrance", "animation": "falcon_swoop", "duration_ms": 3000}` |
| `stackable`, `duration` | stack quantity; time-limited items expire `duration` after activation or grant |
| `requires_privilege` | e.g. Royal-only items |
| `ranked_safe` | magic cards only: may it ever be used in ranked? (default **no**) |

### Ownership and history

- **`InventoryItem`**: user, item, quantity, `expires_at`. Items with different expiry
  dates are kept as separate rows ("2 expire Friday, 1 next month").
- **`ItemTransaction`**: append-only, like the wallet — `+3 rose (reward:tower_r2)`,
  `−1 rose (gift_send)`, `−1 falcon (expired)`. Idempotency key per entry, quantity
  can never go below 0.
- **`ItemActivation`**: when a prop or magic card is used — what, when, until when,
  where (room/game). This is the "usage history".
- **Equipped cosmetics** (`EquippedCosmetic`): one per slot (frame, skin, entrance
  effect, chat theme…). Equipping checks ownership and expiry on the server.
- Expiry runs in the same sweep worker as the turn timer: expired items get an
  `expired` transaction and are unequipped.

### Gifts from inventory

Sending a gift (SOCIAL_MAJLIS §7) can now be paid **from inventory** (owned gift,
−1 item) or **with currency** (bought on the spot). Same transaction, same broadcast,
same rankings. Gift value for rankings stays the catalog's `value_points`, so reward
gifts can be capped from counting towards rankings if that's ever abused.

---

## 5. One reward engine

Every "you got something" — VIP daily, Royal level-up, tower claims, commission,
events, achievements, purchases with bonuses — goes through one function:

```
grant(user, bundle, reason, idempotency_key)
bundle = [ {gold: 5000}, {diamonds: 20}, {item: "rose", qty: 3}, {royal_exp: 50} ]
```

One DB transaction writes every part (wallet, item and EXP ledgers) or none.
`idempotency_key` makes double claims impossible, e.g.
`vip_daily:{user}:{2026-11-15}` or `royal_levelup:{user}:{level 3}`.

`RewardBundle` is admin-configured data; `RewardClaim` records every claim (who,
what, when, key). Reward history screens read `RewardClaim`.

### Daily resets and device time

- The **server's clock** decides. The phone's time is never used.
- Days reset at a fixed **reward-day boundary** (e.g. 00:00 Bahrain time, UTC+3,
  configurable), the same for everyone.
- Streaks are computed on the server from `RewardClaim` history. Missed-day rule is
  configurable: reset the streak, or allow one grace day.

---

## 6. Store and purchases

### Product catalog (admin)

`StoreProduct`: store product IDs (Apple + Google), kind (`consumable` for
gold/diamonds, `subscription` for VIP), currency + amount, bonus amount, badge
(`popular`, `best_value`, `limited`), display order, availability window, regions,
first-purchase-only flag, max purchases per user. The Store screen asks the server
which products to show, then asks the store SDK for their **localised prices**.

### Purchase flow

```
App: tap package → confirm
  → Apple / Google payment sheet
  → store returns a signed purchase (receipt / purchase token)
App → server: POST /api/store/purchases {platform, product_id, receipt/token}
Server:
  1. Verify with Apple (App Store Server API) or Google (Play Developer API)
  2. Store transaction ID seen before? → return the earlier result (no double grant)
  3. Record Purchase (platform, store transaction id, product, price, country, status)
  4. grant(): amount + bonus + first-purchase bonus + recharge-ticket bonus + Royal EXP
  5. Google: acknowledge/consume the purchase (unacknowledged purchases are refunded
     after 3 days)
  6. Commit → realtime wallet_updated → app plays success animation
```

- **Pending / interrupted purchases:** the app re-sends unfinished purchases on next
  launch; the server's idempotency makes that safe.
- **Refunds:** Apple and Google send refund notifications to the server, which writes
  a `reversal`. If the currency was already spent, the balance goes to 0 and the rest
  is recorded as debt that later income repays (SOCIAL_MAJLIS §5).
- **Fake receipts / replays:** rejected by store verification and the unique store
  transaction ID.
- **Region:** taken from the store's country (storefront), not the IP address.
- **Promotions:** first-purchase bonus, limited-time packages, bonus percentages and
  eligibility rules are server data. Real-money *discounts* use the stores' own offer
  tools (introductory and promotional offers).
- **Recharge tickets** (§4 item): "+20% bonus diamonds on your next purchase of 1,800+"
  — the ticket is consumed and the bonus granted inside the same purchase transaction.

### Build or use a service?

Verifying purchases and following subscription renewals across both stores is
precise work. A purchase-management service (RevenueCat is the best known) handles
store APIs and sends our server webhooks; **our server still grants everything
through our ledgers**, so it stays authoritative. Building it ourselves avoids a
third party but takes longer. See §22.

---

## 7. VIP subscriptions

### Tiers are data

`VipTier`: code, name, rank (for upgrade/downgrade order), store product IDs (monthly;
other durations later), badge, frame, colour, daily reward bundle, monthly reward
bundle, privilege grants (§9). Knight and Baron are two rows; **VIP Emperor or King
later = a new row + store products, no code change.** Baron inheriting Knight's
benefits is a setting (`inherits_from`).

### `Subscription`

`id, user, tier, status, started_at, current_period_end, auto_renew, platform,
original_transaction_id, latest_transaction_id, grace_until, cancelled_at`.

### Lifecycle (driven by store notifications + verification)

```
            purchase verified
 (none) ─────────────────────► active ──renewal──► active
                                 │  │
                 billing problem │  │ user turns off auto-renew
                                 ▼  ▼
                      grace_period  cancelled (still active until period end)
                       │      │            │
               fixed ◄─┘      └─► billing_retry (VIP off) ──► expired
                                                     refund ─► revoked (VIP off now)
```

- Apple **App Store Server Notifications** and Google **Real-time Developer
  Notifications** tell the server about renewals, failures, cancellations and refunds.
  A daily job double-checks active subscriptions with the stores.
- **Upgrade** (Knight → Baron): store rules apply (usually immediate); entitlements
  switch when the server sees the new transaction. **Downgrade** takes effect at the
  next renewal.
- **Restore purchases** on a new phone: the app sends its store history; the server
  links the subscription to the account, but one subscription can't be shared by two
  accounts.
- Every change emits `subscription_updated` and recomputes entitlements.

### VIP daily rewards

Claim once per reward-day while VIP is active (§5). Tier decides the bundle. The
claim screen shows today's reward, the streak, the countdown to the next reset and
the history. A Baron who claims, then downgrades, can't claim Baron's reward again
the same day (idempotency key per day, not per tier).

---

## 8. Royal Level and Royal EXP

Long-term progression, separate from account level and from competitive rating.

### Royal EXP ledger

`RoyalExpTransaction`: user, amount, source, reference, `idempotency_key`,
`total_after`, created_at. Append-only. Royal EXP never comes from the app.

Sources are admin rules (`RoyalExpRule`): source, EXP per unit, daily cap, active.
Placeholders:

| Source | EXP | Cap |
|---|---|---|
| Purchase | 1 per US cent spent | none |
| VIP subscription | 500 per month (Knight), 2,000 (Baron) | — |
| Games (online, not bot) | 5 per game | 100 / day |
| Gifts sent | 1 per 100 gift value points | 500 / day |
| Daily missions, events | per reward bundle | — |

Caps and "bot games don't count" stop farming.

### Levels are data

`RoyalLevel`: level, cumulative EXP required, badge, frame, logo, colour, level-up
reward bundle, privilege grants. Royal 0 = 0 EXP. Adding Royal 5, 6, 7 = new rows.
Placeholder curve: R1 = 1,000 · R2 = 7,000 · R3 = 30,000 · R4 = 100,000.

The prompt's example: **1,160 EXP, Royal 1, next level 7,000, 5,840 to go**.

### Level-up (idempotent)

When an EXP grant crosses a threshold, in the same transaction:

1. Write `RoyalLevelUp (user, level)` — **unique per user + level**, so it can't happen twice
2. `grant()` the level's reward bundle with key `royal_levelup:{user}:{level}`
3. Recompute entitlements
4. Write domain event `royal_level_up` → profile badge, moment, notification

The app then plays the level-up sequence: animation → new badge → unlocked privileges
→ rewards. If it was offline, it shows the sequence on next open from the
unacknowledged level-up record.

### Royal Level screen

Header (Royal Level, close, current badge) · progress (level, EXP, required,
remaining, %) · level browser (Royal 0 … latest, swipe) · privileges for the
selected level: unlocked, locked, **new at this level** · rewards for reaching it.
Future levels can be inspected but nothing in them can be claimed. Everything on the
screen comes from server config.

---

## 9. Entitlement engine

One place answers "may this user do X, and how much?". No scattered
`if user.isVip` checks.

### Data

- **`Privilege`** (catalog): `code`, name, description, icon, `value_type`
  (`flag` · `number` · `limit`), `merge` (`any` · `max` · `sum`), category.
- **`PrivilegeGrant`**: `source_type` (`royal_level` · `vip_tier` · `item` ·
  `event` · `admin`), `source_key` (e.g. `royal:3`, `vip:baron`), `privilege`,
  `value`, optional dates, `mode` (`grant` or `revoke`).
- **`UserPrivilegeOverride`**: admin per-user allow/deny with reason and end date.

### Rules

1. Collect the user's active sources: Royal level, active VIP tier(s), active items
   with privileges, running events, admin overrides.
2. **Inheritance:** Royal N includes all grants of Royal 0…N unless a higher level
   explicitly revokes or changes one. Same for VIP tiers with `inherits_from`.
3. **Merge** per privilege: flags = any source grants it; numbers = highest (or sum,
   if configured). Example: `visitor_history_limit` = max(Royal 2: 100, Baron: 200) = 200.
4. Admin **deny** override wins over everything.

### Using it

```python
# server — the only place that decides
entitlements.has(user, "full_room_access")
entitlements.value(user, "visitor_history_limit")   # → 200
```

```dart
// app — for showing and hiding UI only; the server re-checks every action
ref.watch(entitlementsProvider).has(Privilege.voiceMessaging)
```

- Snapshot cached per user (Redis), rebuilt on level-up, subscription change, item
  activation/expiry or admin change; sent to the app as `entitlements_updated`.
- **Unknown codes are fine:** the app lists privileges it doesn't know using the
  name, icon and description from the catalog. A new privilege that only changes
  display needs no app update; one that adds new behaviour needs code once, then
  stays configurable.

---

## 10. Privilege catalog

Starting catalog, with what each one actually does in Dice Majlis. Which Royal levels
or VIP tiers grant which values is **admin data**, so the level lists in the prompt
become seed data, not code.

| Code | Type | What it does | Enforced in |
|---|---|---|---|
| `game_exp_bonus` | number (%) | Bonus account XP from online games (not rating) | stats handler |
| `higher_exp_limit` | number | Raises the daily XP cap | stats handler |
| `super_fragment_exchange` | flag | Unlocks premium offers in Fragment Exchange | exchange |
| `visitor_history` | limit | Visitors kept and shown (e.g. 20 → 500) and retention days | profile |
| `stealth_visit` | flag | Visits aren't recorded in the other person's history | profile |
| `royal_logo` | flag | Royal emblem next to the name | profile, lists, chat |
| `photo_enlarge` | flag | Others can open your avatar full-size | profile |
| `royal_items` | flag | Can buy/receive Royal-only items | store, items |
| `display_on_top` | number (weight) | Higher in room online lists and friend lists | social sort (§12) |
| `priority_ranking` | number (weight) | Higher in **social** lists only, never competitive | social sort (§12) |
| `royal_profile_frame` | flag | Unlocks the level's frame | cosmetics |
| `skin_sync`, `theme_sync` | flag | Your profile skin/theme also styles rooms you own | rooms |
| `pin_friends` | limit | Number of friends you can pin on top | friends |
| `royal_sticker` | flag | Royal sticker pack | chat |
| `full_room_access` | flag | Enter rooms that are at their online cap | rooms |
| `exclusive_launch_screen` | flag | Royal welcome screen after app start | app |
| `profile_page_skin` | flag | Custom profile background | profile |
| `announcement_image` | flag | Images in room announcements | rooms |
| `royal_reward_tower` | flag | Access to the Reward Tower | tower |
| `longer_bio` | limit | Bio length (e.g. 80 → 300 characters) | profile |
| `customer_service_priority` | number (tier) | Support queue priority | support |
| `royal_app_icon` | flag | Choose a Royal app icon (icons ship in the app) | settings |
| `voice_messaging` | flag | Send voice messages in private chat | chat |
| `recharge_ticket` | number | Recharge tickets granted each month | monthly job |
| `super_value_surprise` | number | Free surprise draws per day | surprise |
| `daily_gift_commission` | flag | Access to gift-commission tasks | commission |
| `gif_privileges` | flag | Send GIFs in chat | chat |
| `vip_badge`, `vip_room_create`, `vip_room_access` | flag | VIP identity and VIP rooms | profile, rooms |
| `entrance_effect` | flag | Entrance animation when joining a room | rooms |
| `premium_message_style` | flag | Styled chat bubbles / name colour | chat |

---

## 11. Reward Tower, fragments, surprises, gift commission

### Royal Reward Tower

Floors (`RewardTowerFloor`): required Royal EXP or level, reward bundle, optional
privilege. The tower screen shows claimed, claimable, locked and upcoming floors, with
progress to the next one. A claim calls `grant()` with key
`tower:{user}:{season}:{floor}`. Towers can be seasonal (reset per season) or
permanent.

### Super Fragment Exchange

`ExchangeOffer`: fragment cost, reward bundle, stock, per-user limit, cooldown,
required privilege, dates. Exchange = one transaction: lock fragment wallet → check
limits and cooldown → −fragments → `grant()`. History from the ledgers.

### Super Value Surprise

`ProbabilityTable`: versioned list of `(weight, reward bundle)`; weights must add up;
tables can't be edited once live (a new version is created instead). A draw:

1. Check the user has a draw left (privilege count or owned chest item)
2. Server picks with the secure RNG (same one as the dice)
3. Log `SurpriseDraw` (user, table version, random value, result) and `grant()`

**Odds are shown in the app before every draw.** Default: draws come only from free
sources (Royal privilege, events, earned chests). Paid draws stay off until checked
per country (§2).

### Daily Gift Commission

Daily tasks such as "send gifts worth 1,000 points today" with Royal-level-based
rewards. Progress comes from `gift_sent` events; resets at the reward-day boundary;
claim through `grant()` with key `commission:{user}:{day}:{task}`. Rewards are in-game
only.

---

## 12. Social priority and visitor history

### Configurable social sort

Friend lists and room member lists use one scoring function with **admin-set
weights**, not fixed rules:

```
score = pinned  (always first, up to pin_friends limit)
      + w_online   × is_online
      + w_display  × display_on_top
      + w_priority × priority_ranking
      + w_recent   × recent_interaction
```

Weights live in config and can be tuned live. Competitive leaderboards and
matchmaking never use this score.

### Visitor history

`ProfileVisit`: viewer, viewed, first and last visit of the day, count. One row per
viewer per day (upsert), so busy profiles don't explode the table.

- Shown: newest first, limited by the owner's `visitor_history` value; older rows are
  deleted after the longest retention (e.g. 90 days).
- Not recorded: blocked users, visitors with `stealth_visit` active, the owner.
- VIP/Royal badges shown on visitors; filters (today / week / VIP only) for those who
  have the privilege.
- The privacy policy must say profile visits are visible to the profile owner.

---

## 13. Rooms, chat and customisation

### Room privileges (server-checked on every join/action)

- **VIP rooms:** `MajlisRoom.access_rule` (e.g. `privilege:vip_room_access`). Creating
  one needs `vip_room_create`.
- **Full rooms:** joining past the online cap needs `full_room_access`.
- **Entrance effects:** on join, the server reads the user's equipped entrance effect
  and broadcasts it with `member_joined` (only for effects they own and may use).
- **Announcements with images:** `announcement_image`.
- **Room customisation:** room themes are cosmetic items; `skin_sync`/`theme_sync`
  apply the owner's equipped theme.

### Chat privileges

| Feature | Privilege | Notes |
|---|---|---|
| Voice messages (private chat) | `voice_messaging` | Max length, stored files, reportable; automatic deletion after N days |
| Premium / Royal stickers | sticker pack item or `royal_sticker` | Packs are items |
| GIFs | `gif_privileges` | Start with a curated GIF set; an external GIF search needs strict content filtering |
| Styled messages, name colour | `premium_message_style` | Chat theme cosmetic |
| VIP/Royal badge by name | automatic | From entitlements |

### Customisation and skin/theme sync

Profile frames, skins, logos, themes, avatar effects, backgrounds, name styles,
stickers, badges and entrance effects are all cosmetic items (§4), equipped per slot,
with assets from the CDN. "Sync" means one equipped choice applies everywhere it's
shown: profile, room seat, chat bubble, game board.

---

## 14. Customer support priority

`SupportTicket`: user, category, messages, attachments, status, **priority** (Standard
/ VIP / Royal priority, from `customer_service_priority` at creation and stored on the
ticket), entitlement snapshot (VIP tier, Royal level, recent purchases), assigned
agent. The admin queue sorts by priority, then age. A dedicated helpdesk tool can
replace the queue later; the priority logic stays.

---

## 15. Security and anti-cheat

| Never trusted from the app | Protection |
|---|---|
| Balances, prices, amounts | Server catalog + ledgers; app only sends product/item codes |
| "Payment succeeded" | Server verification with Apple/Google; unique store transaction ID |
| Replayed or fake receipts | Verification + idempotency |
| Double claims (daily, tower, level-up, exchange) | Idempotency keys + unique constraints |
| Device-time tricks | Server clock and reward-day boundary only |
| Negative balances / item counts | DB check constraints + row locks |
| Duplicated gifts or items | Item ledger with locks; every change is a ledger row |
| Royal EXP / level edits | EXP only via rules; level computed from the ledger |
| VIP / subscription status | Store notifications + verification; entitlements computed on the server |
| Modified requests | Validation + entitlement check on every endpoint and socket event |
| Abuse with many accounts | Caps per source, bot games excluded, device-link flags, admin review |

Plus: nightly audits for wallet **and item** ledgers, alerts on unusual grants, admin
actions logged, rate limits on store, claim and exchange endpoints.

---

## 16. Real-time updates

Each user gets a personal channel on `/ws/v1/` (`user:{id}`), sent only after the
change is committed:

`wallet_updated {currency, balance, transaction_id}` · `inventory_updated` ·
`royal_exp_gained` · `royal_level_up` · `entitlements_updated` ·
`subscription_updated` · `reward_granted` · `purchase_completed` ·
`gift_received_private`.

If the app was offline, it refetches wallet, inventory, entitlements and pending
level-ups on reconnect, so missing an event never leaves wrong numbers on screen.

---

## 17. Admin, analytics and balancing

### Admin (Django admin first, a custom panel later)

Store products and promotions · VIP tiers, benefits and rewards · Royal levels, EXP
rules and privileges · privilege catalog and grants · gift and item catalogs ·
probability tables · reward bundles, tower floors, exchange offers, commission tasks ·
social-sort weights · support queue. Every config change is versioned and logged
(who, when, before/after); time-limited content has start/end dates; validation stops
mistakes (odds must add up, level EXP must increase).

### Analytics

- **From the ledgers** (exact): currency inflow by source, outflow by sink, average
  balances, daily spend, gift economy, reward economy, Royal EXP by source, level-ups.
- **Product events** (app analytics): store opened, product viewed, purchase started /
  failed / completed, subscription started / renewed / cancelled, claims.
- **Health dashboard:** inflow vs outflow per currency, purchase and VIP conversion,
  Royal level distribution, premium vs free retention. Balancing is done by changing
  config, never by rebuilding the app.

---

## 18. Database entities

How the prompt's entity list maps to this design:

| Prompt | Here |
|---|---|
| User | `accounts.User` |
| CurrencyWallet, CurrencyTransaction | `WalletAccount`, `WalletTransaction` (gold, diamonds, fragments) |
| Product, Purchase | `StoreProduct`, `Purchase` |
| Subscription, SubscriptionEntitlement, VipTier, VipBenefit | `Subscription`, `VipTier`; benefits = `PrivilegeGrant` + reward bundles |
| RoyalLevel, RoyalExpTransaction | `RoyalLevel`, `RoyalExpTransaction`, `RoyalExpRule`, `RoyalLevelUp` |
| RoyalPrivilege, UserRoyalPrivilege | `Privilege`, `PrivilegeGrant`, `UserPrivilegeOverride` (+ cached snapshot) |
| Reward, RewardClaim, DailyReward, DailyMission | `RewardBundle`, `RewardClaim`, `DailyTask` |
| Gift, GiftInventory, GiftTransaction | `GiftDefinition` + `ItemDefinition`, `InventoryItem`, `GiftTransaction` |
| MagicCard(Inventory), Prop(Inventory), Cosmetic, UserCosmetic | `ItemDefinition` (types), `InventoryItem`, `ItemTransaction`, `ItemActivation`, `EquippedCosmetic` |
| RewardTower | `RewardTowerFloor` |
| Fragment, FragmentTransaction | `fragment` currency in the wallet ledger; `ExchangeOffer` |
| RechargeTicket | `recharge_ticket` item type |
| VisitorHistory | `ProfileVisit` |
| SupportTicket | `SupportTicket`, `SupportMessage` |
| — | `ProbabilityTable`, `SurpriseDraw`, `ConfigChange` (audit) |

Key constraints and indexes: unique `(platform, store_transaction_id)` on `Purchase`;
unique `(user, level)` on `RoyalLevelUp`; unique `idempotency_key` per ledger account;
`quantity >= 0` and `balance >= 0` checks; indexes on `(user, created_at)` for every
ledger, `(viewed, last_visit_at)` on `ProfileVisit`, `(status, priority, created_at)`
on `SupportTicket`.

New backend apps: `store`, `vip`, `royal`, `entitlements`, `items`, `rewards`,
`support` (next to `wallet`, `gifts`, `cosmetics` → `items` absorbs cosmetics).

---

## 19. Flutter modules and state

Following the prompt's structure, merged with SOCIAL_MAJLIS §15:

```
lib/core/entitlements/        EntitlementService + entitlementsProvider (used everywhere)
lib/features/
├── economy/   wallet/ · transactions/          (replaces features/wallet)
├── store/     products/ · purchases/ · promotions/
├── vip/       tiers/ · subscriptions/ · benefits/ · daily_rewards/
├── royal/     levels/ · experience/ · privileges/ · rewards/ · reward_tower/
├── inventory/                                  shared data layer for all item types
├── gifts/     catalog/ · inventory/ · sending/ · animation/
├── magic_cards/ · props/ · cosmetics/
├── exchange/  (fragments) · surprise/ · commission/
├── profile/ · social/ (incl. visitor history) · support/
```

- **Riverpod providers:** wallet, store catalog, purchases, VIP status, Royal
  level/EXP, entitlements, inventory per type, rewards, cosmetics, visitor history.
  Each is refreshed by the matching real-time event.
- **Freezed models** for every payload; config-driven lists (levels, tiers,
  privileges, products) are rendered from data, never hard-coded in widgets.
- **Purchases:** the official `in_app_purchase` plugin (or the chosen service's SDK)
  behind a `PurchaseRepository`, so tests can use a fake store.
- Every screen has loading, error, empty and offline states; dark and light themes.

---

## 20. Testing

| Kind | Must cover |
|---|---|
| Unit | Entitlement merging and inheritance; Royal level from EXP; reward-day boundaries and streaks; probability table validation; social sort |
| Repository / API | Store catalog, purchases, claims, exchange, equip, visitor history, support |
| Purchase flow | Valid purchase; **same receipt twice**; fake receipt; pending purchase finished later; refund after spending; first-purchase bonus once; recharge ticket consumed once; Google acknowledgement |
| Subscriptions | New, renew, cancel, grace, billing retry, expire, refund, upgrade, downgrade, restore on second device, one subscription on two accounts |
| Economy security | Concurrent spends from one wallet; double claims (same second, two devices); device-time change; negative balance and item count; EXP from modified requests; level-up twice; expired items can't be used |
| Integration | Purchase → wallet → Royal EXP → level-up → entitlements → room access, end to end |
| Flutter | Store renders server products with store prices; unknown privilege rendered generically; level-up sequence; offline/reconnect refresh |
| Manual | Apple sandbox / TestFlight and Google Play license testers before launch |

The prompt's final acceptance list is adopted as the **exit checklist** for phases 9–11.

---

## 21. Build order

### Foundations move earlier (so nothing is rebuilt later)

| Where | Change |
|---|---|
| Phase 3, **S4** | Becomes the **item system** (definitions, inventory, item ledger, equip) with cosmetics as its first item type |
| Phase 4, **S6** | Wallet ledger includes `fragment` currency and `balance_before` |
| Phase 4, new **S6b** | **Reward engine** (`grant()`, bundles, claims, reward-day boundary) + daily login reward |
| Phase 4, new **S6c** | **Entitlement engine** with the privilege catalog and admin grants (no purchases yet) |

### Phase 9 — Store and purchases

| Step | Build | Done when |
|---|---|---|
| M1 | Store catalog (admin) + Store screen with store prices; purchase-service decision implemented | Admin changes a badge/order and the app shows it |
| M2 | Consumable purchases (gold, diamonds) with server verification, refunds, Google acknowledgement | All purchase-flow tests pass; sandbox purchases work on both stores |
| M3 | Promotions: first-purchase bonus, limited packages, regions, recharge tickets | Bonus applied exactly once |
| M4 | Purchase history and transaction history screens | Every ledger row visible to the user |

### Phase 10 — VIP and Royal

| Step | Build | Done when |
|---|---|---|
| M5 | Subscription engine + VIP tiers (Knight, Baron) from config | Full lifecycle tests pass; restore works |
| M6 | VIP daily rewards with streaks | Device-time change can't claim twice |
| M7 | Royal EXP ledger, rules, levels, idempotent level-up | Crossing a level twice grants once |
| M8 | Royal privileges wired to entitlements + Royal Level screen | Future levels browsable, nothing claimable |
| M9 | Royal Reward Tower | Claims are server-validated and once-only |
| M10 | Profile, room, chat and social-sort integration of VIP/Royal | VIP room blocks non-VIP on the server |

### Phase 11 — Premium items and extras

| Step | Build | Done when |
|---|---|---|
| M11 | Magic cards and props (activation, effects, usage history) | Expired items can't be used; ranked blocks gameplay cards |
| M12 | Fragment Exchange | Limits and cooldowns enforced |
| M13 | Super Value Surprise (free draws, odds shown, logged) | Draw results reproducible from the log |
| M14 | Daily Gift Commission | Resets at the reward-day boundary |
| M15 | Visitor history (+ stealth) | Limits follow entitlements; blocked users never appear |
| M16 | Chat privileges: voice messages, stickers, GIFs, styles | Each checked by the entitlement engine on the server |
| M17 | Support tickets with priority | Royal tickets sort above standard |
| M18 | Economy dashboard and balancing tools | Inflow/outflow per currency visible daily |

Then **Phase 12: voice (WebRTC SFU) and polish.**

---

## 22. Decisions needed

1. **Real money: answered yes.** Gold, diamonds and VIP are sold through App Store /
   Google Play. (Updates SOCIAL_MAJLIS §18.)
2. **Purchase handling:** a purchase-management service (e.g. RevenueCat) or our own
   store verification? I recommend a service, at least for subscriptions; our ledgers
   stay the source of truth either way.
3. **Super Value Surprise:** free-only (recommended), or also purchasable (odds shown,
   legal check per country first)?
4. **Reward-day reset time:** 00:00 Bahrain time (UTC+3) for everyone?
5. **Gift cash-out:** still assumed **no** (Daily Gift Commission pays in-game rewards only).
6. **Minimum age and spending limits** for purchases.
7. **Magic cards in games:** casual games only, never ranked? (Recommended.)
