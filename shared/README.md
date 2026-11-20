# shared/

Files used by both the backend and the app.

## `ludo/engine_vectors.json`

The Ludo rules written down as data. The server's Python engine
(`backend/core/ludo_engine/`) plays seeded games and records, for every action,
what it answered: the events, the error code for a refused action, the bot's choice
and full state snapshots. The app's Dart engine (offline games,
`frontend/dice_majlis_app/lib/features/ludo/domain/engine/`) must give exactly the
same answers. Same vectors passing in both = same rules.

Generated — never edit by hand. After changing a rule in Python (from `backend/core`):

```bash
python -m ludo_engine.vectors        # rewrites the file
python manage.py test ludo_engine    # checks it is up to date
```

Then run `flutter test test/ludo_engine_vectors_test.dart` in the app and change the
Dart engine until it passes.
