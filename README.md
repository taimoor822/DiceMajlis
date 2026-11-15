# 🎲 Dice Majlis

**Multiplayer Ludo with the feel of a Majlis.** Play with friends or a bot, chat,
compete and come back every day. Ludo is the game; the social Majlis is the
platform.

Flutter app (Android / iOS) + Django backend with real-time WebSockets.

> **Status: early development.** Online games work end to end. The UI is
> functional but not final — the Majlis visual redesign is planned
> (see [roadmap](#roadmap)).

---

## What works today

- **Private rooms** — create a room, share the 4-letter code, 2–4 players
- **Play against a bot** — start alone and "Majlis AI" joins opposite you
- **Server-controlled game** — the server rolls the dice and checks every move,
  so the app can't cheat
- **Full Ludo rules** — enter on a 6, captures, safe squares, extra turns,
  three sixes ends your turn, exact roll to get home
- **30-second turn timer** — if a player is idle, the server plays for them;
  miss 3 turns in a row and you're removed, so a game never freezes
- **Reconnect** — if the connection drops, the app reconnects and gets the full
  game back (on web, even after a page refresh). Reopening a closed phone app
  comes with accounts in step 1.5
- **Move log** — every action is saved and any game can be replayed exactly
  (viewable in the Django admin)

## Tech stack

| | |
|---|---|
| App | Flutter, Dart, Dio, `web_socket_channel` |
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
│       └── game/                # rooms, REST API, WebSocket, bots, turn timer
├── frontend/
│   └── dice_majlis_app/         # Flutter app
├── docs/
│   ├── ARCHITECTURE.md          # technical foundation and design decisions
│   └── planning.md              # progress tracker
└── docker-compose.dev.yml       # Redis + PostgreSQL for local development
```

## Run it locally

**You need:** Python 3.12+, Flutter (Dart 3.10+), and Redis.
The easiest way to get Redis is Docker:

```bash
docker compose -f docker-compose.dev.yml up -d redis
```

### 1. Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate              # Windows: venv\Scripts\activate
pip install -r requirements.txt
pip install "uvicorn[standard]"       # WebSocket server (moves into requirements in step 1.3)
cp ../.env.example ../.env            # defaults use SQLite

cd core
python manage.py migrate
uvicorn core.asgi:application --reload --host 0.0.0.0 --port 8000
```

The turn timer starts automatically inside the server.

### 2. App

```bash
cd frontend/dice_majlis_app
flutter pub get
flutter run
```

The app talks to `10.0.2.2:8000` on the Android emulator and `127.0.0.1:8000`
on web. **On a real phone**, change those addresses to your computer's Wi-Fi IP
(for example `192.168.1.20`) in `lib/services/api_service.dart` and
`lib/services/socket_service.dart`, and add that IP to `DJANGO_ALLOWED_HOSTS`
in `.env`. (Step 1.3 replaces this with a build setting.)

> Updating from an older version? Run `python manage.py migrate` and start a new
> game — games started before the rules engine can't be continued.

## Tests

```bash
# Backend: rules engine + API, sockets and turn timer (106 tests)
cd backend/core
python manage.py test

# Rules engine only, without Django
python -m unittest discover -s ludo_engine/tests -t .

# Flutter: board geometry and turn countdown
cd frontend/dice_majlis_app
flutter test test/ludo_path_test.dart test/turn_clock_test.dart
```

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
| **1 — Foundation** (now) | ✅ rules engine · ✅ server-run game · ✅ turn timer · dev setup & CI · app restructure · accounts & login · home dashboard · offline mode |
| 2 — Online multiplayer | Matchmaking, faster real-time protocol, stronger reconnection |
| 3 — Competitive | Ratings, leagues, seasons, leaderboards |
| 4 — Social | Majlis chat rooms, friends, private messages |
| 5 — Economy | Coins, diamonds, rewards, Majlis Pass, cosmetics |
| 6 — Tournaments | Daily and weekly brackets |
| 7 — Polish | Animations, performance, Arabic and Urdu, accessibility |

Step-by-step progress: [docs/planning.md](docs/planning.md).

---

Built by [Taimoor Aziz](https://github.com/taimoor822).
