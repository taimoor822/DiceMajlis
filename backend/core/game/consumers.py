import json
import logging

from asgiref.sync import sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer

from . import services
from .models import Room

logger = logging.getLogger(__name__)


class LobbyConsumer(AsyncWebsocketConsumer):
    """
    Read-only room channel: the server pushes lobby and game updates here.
    Players act through the REST API (which checks their seat secret), never
    through this socket.
    """

    async def connect(self):
        self.room_code = self.scope['url_route']['kwargs']['code'].upper()
        self.group_name = services.group_name(self.room_code)

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        logger.debug("socket joined %s", self.group_name)

        room_info = await self.get_room_info()
        if room_info is None:
            return
        players, snapshot = room_info

        await self.channel_layer.group_send(
            self.group_name,
            {'type': 'players_updated', 'players': players},
        )

        # Joining after the game started (refresh / reconnect): send the full state.
        if snapshot is not None:
            await self.send(text_data=json.dumps(snapshot))
            current = snapshot.get('current_turn_player_id')
            bot_turn = any(p['id'] == current and p['is_bot'] for p in snapshot['players'])
            if bot_turn and snapshot.get('winner_id') is None:
                # Make sure the bot resumes playing.
                await sync_to_async(services.schedule_bots)(self.room_code)

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    # ==================================================
    # Messages from the server (group_send) -> this client
    # ==================================================
    async def players_updated(self, event):
        await self.send(text_data=json.dumps({
            'type': 'players_updated',
            'players': event['players'],
        }))

    async def game_started(self, event):
        # services.game_snapshot(): already in the shape the app expects.
        await self.send(text_data=json.dumps(event))

    async def game_event(self, event):
        # Engine events from game.services: forward the payload unchanged.
        await self.send(text_data=json.dumps(event['payload']))

    # ==================================================
    # DB access
    # ==================================================
    @sync_to_async
    def get_room_info(self):
        """(players, snapshot) for this room; snapshot is None until the game starts."""
        room = Room.objects.filter(code=self.room_code).first()
        if room is None:
            return None
        players = services.players_payload(room)
        snapshot = services.game_snapshot(room) if room.is_started else None
        return players, snapshot
