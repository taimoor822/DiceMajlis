import json
from channels.generic.websocket import AsyncWebsocketConsumer
from .models import Room
from asgiref.sync import sync_to_async


class LobbyConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.room_code = self.scope['url_route']['kwargs']['code']
        self.group_name = f'lobby_{self.room_code}'

        print("🔌 WS CONNECTED:", self.group_name)

        await self.channel_layer.group_add(
            self.group_name,
            self.channel_name
        )

        await self.accept()
        await self.broadcast_players()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(
            self.group_name,
            self.channel_name
        )

    async def broadcast_players(self):
        players = await self.get_players()
        print("📢 BROADCAST PLAYERS:", players)

        await self.channel_layer.group_send(
            self.group_name,
            {
                'type': 'players_updated',
                'players': players,
            }
        )

    async def players_updated(self, event):
        await self.send(text_data=json.dumps({
            'type': 'players_updated',
            'players': event['players'],
        }))

    async def game_started(self, event):
        await self.send(text_data=json.dumps({
            'type': 'game_started'
        }))

    async def dice_rolled(self, event):
        await self.send(text_data=json.dumps({
            'type': 'dice_rolled',
            'dice': event['dice'],
            'next_player_id': event['next_player_id'],
        }))

    @sync_to_async
    def get_players(self):
        try:
            room = Room.objects.get(code=self.room_code)
            players = []

            for p in room.players.all():
                players.append({
                    'id': str(p.id),          # ✅ UUID → string
                    'name': p.name,
                    'color': p.color,
                    'is_host': p.is_host,
                })

            return players

        except Room.DoesNotExist:
            return []

