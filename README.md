# 🎲 Dice Majlis

[![CI](https://github.com/taimoor822/DiceMajlis/actions/workflows/ci.yml/badge.svg)](https://github.com/taimoor822/DiceMajlis/actions/workflows/ci.yml)

**Multiplayer Ludo with the feel of a Majlis.** Play with friends or a bot, chat,
compete and come back every day. Ludo is the game; the social Majlis is the
platform.

Flutter app (Android / iOS) + Django backend with real-time WebSockets.

> **Status: early development.** Online games work end to end, with accounts
> (guest or email), a permanent Player ID and a basic profile. The app has its
> Majlis look (dark navy and gold, plus a light theme) and its main navigation;
> coins come next (see [roadmap](#roadmap)).

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
- **Private rooms** — create a room, share the 4-letter code, 2–4 players
- **Play against a bot** — start alone and "Majlis AI" joins opposite you
- **Server-controlled game** — the server rolls the dice and checks every move,
  so the app can't cheat. Your seat belongs to your account, so nobody can roll
  or move for someone else
- **Clear messages** — if something fails (room full, wrong code, no
  connection), the app says why
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
│       ├── ludo_engine/         # the Ludo rules engine + tests
│       ├── accounts/            # sign-in (guest, email), tokens, Player ID, devices, password reset
│       ├── profiles/            # name, avatar, country, languages, XP/level
│       └── game/                # rooms, REST API, WebSocket, bots, turn timer
├── frontend/
│   └── dice_majlis_app/         # Flutter app
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
# Backend: rules engine, accounts (guest, email, tokens, reset), profiles, API,
# input checks, seats, leaving, sockets, turn timer (190 tests)
cd backend/core
python manage.py test

# Rules engine only, without Django
python -m unittest discover -s ludo_engine/tests -t .

# Flutter: sign-in (guest, email, forgotten password, save account, staying signed
# in, offline retry, sign out, token refresh), profile editing, going back to your
# room, navigation, create/join/waiting-room/leave flow, error messages, routes,
# themes, board (only server-listed tokens move, leave game), server address, countdown
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

All of these are settings in `backend/core/ludo_engine/rules.py`.

## Roadmap

| Phase | What |
|---|---|
| **1 — Playable foundation** (now) | ✅ rules engine · ✅ online game on the engine · ✅ turn timer · ✅ dev setup & CI · ✅ app architecture & Majlis theme · ✅ main navigation · ✅ accounts with Player ID · ✅ email sign-in & profile · currency · local play · multi-game layer · real-time v1 · private rooms v2 · reconnection |
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
