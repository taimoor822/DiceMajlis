import json
from channels.generic.websocket import AsyncWebsocketConsumer
from asgiref.sync import sync_to_async
from .models import Room, Token


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

        # If a client connects after the game started (e.g. refresh), send full state.
        game_state = await self.get_game_state()
        if game_state is not None and game_state.get('is_started') is True:
            await self.send(text_data=json.dumps({
                'type': 'game_started',
                'room_code': game_state['room_code'],
                'current_turn_player_id': game_state['current_turn_player_id'],
                'players': game_state['players'],
                'tokens': game_state['tokens'],
                'last_dice': game_state['last_dice'],
            }))

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
        payload = {'type': 'game_started'}

        # Optional fields (backwards-compatible)
        if 'room_code' in event:
            payload['room_code'] = event['room_code']
        if 'current_turn_player_id' in event:
            payload['current_turn_player_id'] = event['current_turn_player_id']
        if 'players' in event:
            payload['players'] = event['players']
        if 'tokens' in event:
            payload['tokens'] = event['tokens']
        if 'last_dice' in event:
            payload['last_dice'] = event['last_dice']

        await self.send(text_data=json.dumps(payload))

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

    @sync_to_async
    def get_game_state(self):
        try:
            room = Room.objects.get(code=self.room_code)
        except Room.DoesNotExist:
            return None

        players = [
            {
                'id': str(p.id),
                'name': p.name,
                'color': p.color,
                'is_host': p.is_host,
            }
            for p in room.players.all()
        ]

        tokens = [
            {
                'id': str(t.id),
                'player_id': str(t.player_id),
                'position': t.position,
                'is_finished': t.is_finished,
            }
            for t in Token.objects.filter(player__room=room).select_related('player')
        ]

        current_turn_player_id = None
        last_dice = None
        if hasattr(room, 'game'):
            current_turn_player_id = str(room.game.current_turn_id) if room.game.current_turn_id else None
            last_dice = room.game.last_dice

        return {
            'room_code': room.code,
            'is_started': room.is_started,
            'current_turn_player_id': current_turn_player_id,
            'last_dice': last_dice,
            'players': players,
            'tokens': tokens,
        }
