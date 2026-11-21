# 🎲 Dice Majlis

[![CI](https://github.com/taimoor822/DiceMajlis/actions/workflows/ci.yml/badge.svg)](https://github.com/taimoor822/DiceMajlis/actions/workflows/ci.yml)

**Multiplayer Ludo with the feel of a Majlis.** Play with friends or a bot, chat,
compete and come back every day. Ludo is the game; the social Majlis is the
platform.

Flutter app (Android / iOS) + Django backend with real-time WebSockets.

> **Status: early development.** Online games work end to end, with accounts
> (guest or email), a permanent Player ID, a basic profile, and Gold and Diamonds
> with a daily reward. The app has its Majlis look (dark navy and gold, plus a light
> theme) and its main navigation, and offline games (vs the AI or pass-and-play) run
> on the phone with the same rules. The platform is ready for more games (a game
> registry on server and app). Online games run over one live connection, in
> private rooms with ready checks, host controls, invites, custom rules and
> rematches. Reconnection comes next (see [roadmap](#roadmap)).

---

## What works today

- **Accounts** — one tap to play as a guest, or sign up with email and password.
  Every account gets a permanent 9-digit **Player ID**. A guest can **save the
  account** with an email later and keep everything. **Forgot password?** sends a
  6-digit code by email. The app stays signed in (secure phone storage); sign out in
  Settings. Google and Apple sign-in say "coming soon"
- **Profile** — your name, avatar (16 built-in pictures), country, the languages you
  speak, and your level with an XP bar. Home shows your avatar, name, level and Player
  ID. Earning XP from games comes in Phase 2
- **Gold and Diamonds** — balances at the top of Home and a **Wallet** with the full
  history of every change. A **daily reward** grows for 7 days in a row (day 7 adds
  diamonds); miss a day and it starts again. The day changes at midnight Bahrain
  time, by the server's clock. Balances only change on the server, through a ledger
  that can't be edited, and the team can grant or take back currency in the admin
  with a reason. Buying gold and diamonds comes later
- **Live connection** — while you're signed in, the app keeps one live connection
  to the server (signed in with your account, checked every 20 seconds, and it
  reconnects by itself). Today it keeps your Gold and Diamonds up to date: claim the
  daily reward on one phone and Home on your other phone changes at once. Online
  games run on it too: rolls and moves are sent over it, and every update carries the
  game's version, so the board never shows a step twice and loads the whole game
  again if it missed one. A move made on an old picture of the board is refused
  (the board catches up, then you play)
- **Private rooms** — create a room, share the 4-letter code or invite friends by
  their Player ID (the invite shows on their Home at once), 2–4 players. Guests tap
  "I'm ready"; the host starts when everyone is (a 3-second countdown), can lock the
  room to invited players, remove someone, pass the host role, and pick the rules
  (turn time, captures, extra turn on a six, play on for every place). After the
  game, **Play again** starts a rematch with the same people once everyone says yes
- **Play on this phone** — offline games from Game Hub: 2–4 players, each colour a
  person (pass the phone around) or the Majlis AI. Works with no account and no
  connection (Welcome and the "can't reach the server" screen have a button), and
  never touches Gold, Diamonds or ratings. It runs the same rules as the server,
  checked by shared test vectors
- **Play against a bot** — start alone and "Majlis AI" joins opposite you
- **Server-controlled game** — the server rolls the dice and checks every move,
  so the app can't cheat. Your seat belongs to your account, so nobody can roll
  or move for someone else
- **Clear messages** — if something fails (room full, wrong code, no
  connection), the app says why
- **Many games, one platform** — every room knows its game and variant (today:
  Classic Ludo). Game Hub lists the games the server offers; the server runs any game
  in its registry with the same rooms, bots, turn timer and move log, so Domino and
  Jackaroo can plug in later
- **Main navigation** — bottom bar with Events, Game Hub, Battle, Chat and Social;
  Battle in the centre is the Home lobby. Rooms live in Game Hub; sections not built
  yet say "coming soon"
- **Dark and light themes** — pick one in Settings; the phone remembers it
- **Full Ludo rules** — enter on a 6, captures, safe squares, extra turns,
  three sixes ends your turn, exact roll to get home
- **30-second turn timer** — if a player is idle, the server plays for them;
  miss 3 turns in a row and you're removed, so a game never freezes
- **Come back to your game** — if the connection drops, the app reconnects and
  gets the full game back. Close the app (or refresh the web page) and open it
  again: it goes straight back to your waiting room or game
- **Leave properly** — leaving a waiting room gives your seat back (the host role
  passes on); leaving a game asks first, then you forfeit
- **Move log** — every action is saved and any game can be replayed exactly
  (viewable in the Django admin)

## Tech stack

| | |
|---|---|
| App | Flutter 3.38+, Riverpod, GoRouter, Freezed, Dio, `web_socket_channel` |
| Backend | Python, Django 6, Django REST Framework, Django Channels |
| Game rules | `ludo_engine` — pure Python, no framework, fully tested |
| Data | SQLite (dev) or PostgreSQL · Redis for real-time messaging |

Why Django and not NestJS, and the full plan: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Project layout

```
DiceMajlis/
├── backend/
│   ├── requirements.txt
│   └── core/                    # Django project (manage.py lives here)
│       ├── core/                # settings, ASGI, URLs
│       ├── ludo_engine/         # the Ludo rules engine + tests (+ vectors.py: shared test vectors)
│       ├── game_platform/       # game registry: one contract for every game, Ludo's adapter
│       ├── accounts/            # sign-in (guest, email), tokens, Player ID, devices, password reset
│       ├── profiles/            # name, avatar, country, languages, XP/level
│       ├── wallet/              # gold + diamonds: ledger, admin adjustments, audit
│       ├── rewards/             # grant() engine, daily reward
│       ├── realtime/            # the app's one live connection /ws/v1/: sign-in, channels, limits, presence
│       └── game/                # rooms, REST API, WebSocket, bots, turn timer (any game; tables/ = per-game extras)
├── frontend/
│   └── dice_majlis_app/         # Flutter app (with a Dart copy of the engine for offline games)
├── shared/ludo/engine_vectors.json  # rules written down by the Python engine; both engines must pass it
├── CLAUDE.md                    # guide for Claude Code sessions (rules, commands, status)
├── .github/workflows/ci.yml     # tests on every push
├── docs/
│   ├── ARCHITECTURE.md          # technical foundation and design decisions
│   ├── SOCIAL_MAJLIS.md         # profiles, Majlis rooms and gift economy design
│   ├── ROYAL_VIP_ECONOMY.md     # store, VIP, Royal levels, items, entitlements design
│   ├── PLATFORM.md              # multi-game platform, competition, events, feed, admin
│   └── planning.md              # master roadmap (the build order)
└── docker-compose.dev.yml       # Redis + PostgreSQL for local development
```

## Run it locally

**You need:** Python 3.12+ and Flutter 3.38+ (Dart 3.10+). Redis and PostgreSQL are
optional for local development (see the `.env` notes below).

### 1. Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate              # Windows: venv\Scripts\activate
pip install -r requirements.txt
cp ../.env.example ../.env            # SQLite + no Redis needed by default

cd core
python manage.py migrate
uvicorn core.asgi:application --reload --host 0.0.0.0 --port 8000
```

The turn timer starts automatically inside the server. Use `uvicorn` as shown:
plain `python manage.py runserver` doesn't serve WebSockets.

**`.env` options:** `CHANNEL_LAYER=memory` runs without Redis (one server process
only); set it to `redis` and run `docker compose -f docker-compose.dev.yml up -d redis`
for the production-like setup. `DB_ENGINE=postgres` uses the Docker PostgreSQL.

### 2. App

```bash
cd frontend/dice_majlis_app
flutter pub get
flutter run                                   # emulator / simulator / web
```

Without settings, the app talks to `10.0.2.2:8000` on the Android emulator and
`127.0.0.1:8000` on web and the iOS simulator.

**On a real phone**, connect the phone and computer to the same Wi-Fi, find the
computer's IP (for example `192.168.1.20`) and run:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

If `DJANGO_ALLOWED_HOSTS` in `.env` isn't `*`, add that IP to it.

> **Updating from an older version?** Run `pip install -r requirements.txt` and
> `python manage.py migrate`. If your database is from before step 1.6 (accounts),
> it can't be upgraded: stop the server, delete `backend/core/db.sqlite3` (only test
> rooms are lost) and run `migrate` again.

**Forgot password while developing:** there's no email service yet, so the 6-digit
code is printed in the terminal where the server runs (look for "Your code is").

## Tests

```bash
# Backend: rules engine (+ shared vectors up to date), game registry (Ludo adapter,
# a toy second game through rooms, bots and the timer), accounts (guest, email,
# tokens, reset), profiles, wallet ledger, rewards, API, input checks, seats,
# leaving, sockets, turn timer, the live connection /ws/v1/ (sign-in, channels,
# rate limits, retries answered once, presence), game actions over it, private
# rooms (ready, host controls, invites, rules, countdown, rematch) (~334 tests)
cd backend/core
python manage.py test

# Rules engine only, without Django
python -m unittest discover -s ludo_engine/tests -t .

# After changing a rule: write the shared test vectors again (then commit them)
python -m ludo_engine.vectors

# Flutter: sign-in (guest, email, forgotten password, save account, staying signed
# in, offline retry, sign out, token refresh), profile editing, balances, daily
# reward, wallet history, going back to your
# room, navigation, create/join/waiting-room/leave flow, error messages, routes,
# themes, board (only server-listed tokens move, leave game), server address, countdown,
# the Dart engine against every shared vector, offline games (setup, AI turns,
# pass-and-play, results, playing with no account or no server), game registry
# (Game Hub from the server catalog, variants, board picked by game type), the live
# connection (sign-in, reconnects with back-off, token refresh, pings, channels,
# Home balances following the server)
cd frontend/dice_majlis_app
flutter test
```

Every push runs both suites on GitHub (backend on PostgreSQL) — see the CI badge.

## Game rules (defaults)

| Rule | |
|---|---|
| Leave base | Roll a 6 |
| Extra turn | Rolling a 6, capturing a token, or bringing a token home |
| Three sixes in a row | Your turn ends |
| Capture | Land on an opponent's token to send it back to base |
| Safe squares | The four start squares and the four stars |
| Home | Needs the exact roll |
| Turn timer | 30 seconds; after 3 missed turns in a row you're removed |
| Winner | First player with all four tokens home |

All of these are settings in `backend/core/ludo_engine/rules.py`. The app's offline
copy (`lib/features/ludo/domain/engine/`) is checked against it by the shared test
vectors.

## Roadmap

| Phase | What |
|---|---|
| **1 — Playable foundation** (now) | ✅ rules engine · ✅ online game on the engine · ✅ turn timer · ✅ dev setup & CI · ✅ app architecture & Majlis theme · ✅ main navigation · ✅ accounts with Player ID · ✅ email sign-in & profile · ✅ gold, diamonds & daily reward · ✅ local play · ✅ multi-game layer · ✅ real-time v1 · ✅ online games on v1 · ✅ private rooms v2 · reconnection |
| 2 — Player system | XP and levels, inventory and basic customisation, statistics, achievements |
| 3 — Ludo complete | Team mode, variants (Quick, Snakes, Lucky, Jungle, Night, Fight), replays |
| 4 — Multiplayer at scale | Matchmaking, spectators, load testing |
| 5 — Social | Friends, chat, feed, notifications, Majlis rooms, communities |
| 6 — Competition | Ratings, leagues, leaderboards, tournaments |
| 7 — Economy | Shop, gifts, room gifting, real-money store |
| 8 — Events | Missions, events, Reward Tower, seasonal content |
| 9 — VIP & collections | VIP, Royal levels, collections, premium items |
| 10–12 | Admin dashboard · polish · production |
| 13 | New games: Domino, Jackaroo |

Designs: [PLATFORM.md](docs/PLATFORM.md) · [SOCIAL_MAJLIS.md](docs/SOCIAL_MAJLIS.md) ·
[ROYAL_VIP_ECONOMY.md](docs/ROYAL_VIP_ECONOMY.md).
Step-by-step progress: [docs/planning.md](docs/planning.md).

---

Built by [Taimoor Aziz](https://github.com/taimoor822).
