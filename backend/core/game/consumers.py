import json
from channels.generic.websocket import AsyncWebsocketConsumer
from asgiref.sync import sync_to_async
from .models import Room


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

    # ==================================================
    # 🔄 PLAYERS
    # ==================================================
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

    # ==================================================
    # 🎮 GAME FLOW EVENTS
    # ==================================================
    async def game_started(self, event):
        await self.send(text_data=json.dumps({
            'type': 'game_started',
        }))

    async def dice_rolled(self, event):
        await self.send(text_data=json.dumps({
            'type': 'dice_rolled',
            'player_id': event['player_id'],
            'dice': event['dice'],
        }))

    async def token_moved(self, event):
        await self.send(text_data=json.dumps({
            'type': 'token_moved',
            'player_id': event['player_id'],
            'token_id': event['token_id'],
            'from': event['from'],
            'to': event['to'],
            'dice': event['dice'],
            'killed': event['killed'],
        }))

    async def turn_changed(self, event):
        await self.send(text_data=json.dumps({
            'type': 'turn_changed',
            'player_id': event['player_id'],
        }))

    async def game_finished(self, event):
        await self.send(text_data=json.dumps({
            'type': 'game_finished',
            'winner_id': event['winner_id'],
        }))

    # ==================================================
    # 🧠 DB ACCESS
    # ==================================================
    @sync_to_async
    def get_players(self):
        try:
            room = Room.objects.get(code=self.room_code)
            return [
                {
                    'id': str(p.id),       # UUID safe
                    'name': p.name,
                    'color': p.color,
                    'is_host': p.is_host,
                }
                for p in room.players.all()
            ]
        except Room.DoesNotExist:
            return []
