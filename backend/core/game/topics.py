"""
The game app's socket channels (registered in ``GameConfig.ready``):

- ``room/<room id>``: who is seated (``players_updated``) and ``game_started``.
  Members of the room only.
- ``game/<game id>``: the game's events (``dice_rolled``, ``token_moved``, …), each
  with the state ``version``. Seated players only (spectators come in Phase 4).

A new subscriber first gets the current state, so it never misses anything.
What is sent afterwards is published by ``game.services.broadcast`` (the one
place that sends game messages).
"""

from __future__ import annotations

from realtime import topics
from realtime.protocol import ProtocolError

from . import services
from .models import Game, Room


def _seated(user, room) -> bool:
    return room.players.filter(user=user, is_bot=False).exists()


def _snapshot_data(room) -> dict:
    """The ``game_started`` snapshot without its legacy ``type`` key."""
    snapshot = services.game_snapshot(room)
    snapshot.pop("type", None)
    return snapshot


class RoomTopic(topics.Topic):
    kind = "room"

    def parse_key(self, key):
        return topics.uuid_key(key)

    def authorize(self, user, key):
        room = Room.objects.filter(id=key).first()
        if room is None:
            raise ProtocolError("channel_not_found", "No such room")
        if not _seated(user, room):
            raise ProtocolError("not_in_room", "You have no seat in this room")

    def initial_events(self, user, key):
        room = Room.objects.filter(id=key).first()
        if room is None:
            return []
        channel = topics.Channel(self.kind, key)
        events = [
            topics.event(channel, "players_updated", {"players": services.players_payload(room)}),
        ]
        if room.is_started:
            snapshot = _snapshot_data(room)
            events.append(topics.event(channel, "game_started", snapshot, version=snapshot.get("version")))
        return events


class GameTopic(topics.Topic):
    kind = "game"

    def parse_key(self, key):
        return topics.number_key(key)

    def authorize(self, user, key):
        game = Game.objects.select_related("room").filter(id=key).first()
        if game is None:
            raise ProtocolError("channel_not_found", "No such game")
        if not _seated(user, game.room):
            raise ProtocolError("not_in_game", "You have no seat in this game")

    def initial_events(self, user, key):
        game = Game.objects.select_related("room").filter(id=key).first()
        if game is None:
            return []
        snapshot = _snapshot_data(game.room)
        return [
            topics.event(
                topics.Channel(self.kind, key), "state_snapshot", snapshot, version=snapshot.get("version")
            )
        ]


def register() -> None:
    topics.register(RoomTopic())
    topics.register(GameTopic())
