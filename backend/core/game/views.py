import random
import string

from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .models import Room, Player, Game
from .serializers import RoomSerializer, PlayerSerializer


# =========================
# UTILS
# =========================

def generate_room_code():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))


def broadcast_players(room):
    channel_layer = get_channel_layer()

    players = []
    for p in room.players.all():
        players.append({
            'id': str(p.id),        # ✅ UUID → string
            'name': p.name,
            'color': p.color,
            'is_host': p.is_host,
        })

    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'players_updated',
            'players': players,
        }
    )

# =========================
# CREATE ROOM
# =========================

@api_view(['POST'])
def create_room(request):
    max_players = request.data.get('max_players', 4)
    player_name = request.data.get('name', 'Player 1')
    color = request.data.get('color', 'red')

    code = generate_room_code()
    while Room.objects.filter(code=code).exists():
        code = generate_room_code()

    room = Room.objects.create(
        code=code,
        max_players=max_players
    )

    player = Player.objects.create(
        room=room,
        name=player_name,
        color=color,
        is_host=True
    )

    return Response(
        {
            'room': RoomSerializer(room).data,
            'player': PlayerSerializer(player).data,
        },
        status=status.HTTP_201_CREATED
    )


# =========================
# JOIN ROOM
# =========================

@api_view(['POST'])
def join_room(request):
    code = request.data.get('code')
    player_name = request.data.get('name', 'Player')
    color = request.data.get('color', 'blue')

    if not code:
        return Response(
            {'error': 'Room code is required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        room = Room.objects.get(code=code)
    except Room.DoesNotExist:
        return Response(
            {'error': 'Room not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    if room.is_started:
        return Response(
            {'error': 'Game already started'},
            status=status.HTTP_400_BAD_REQUEST
        )

    if room.players.count() >= room.max_players:
        return Response(
            {'error': 'Room is full'},
            status=status.HTTP_400_BAD_REQUEST
        )

    player = Player.objects.create(
        room=room,
        name=player_name,
        color=color,
        is_host=False
    )

    # 🔔 WebSocket: update players list
    broadcast_players(room)

    return Response(
        {
            'room': RoomSerializer(room).data,
            'player': PlayerSerializer(player).data,
        },
        status=status.HTTP_200_OK
    )


# =========================
# START GAME (HOST ONLY)
# =========================

@api_view(['POST'])
def start_game(request):
    code = request.data.get('code')
    player_id = request.data.get('player_id')

    if not code or not player_id:
        return Response(
            {'error': 'code and player_id required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        room = Room.objects.get(code=code)
    except Room.DoesNotExist:
        return Response(
            {'error': 'Room not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    if room.is_started:
        return Response(
            {'error': 'Game already started'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        host = Player.objects.get(
            id=player_id,
            room=room,
            is_host=True
        )
    except Player.DoesNotExist:
        return Response(
            {'error': 'Only host can start the game'},
            status=status.HTTP_403_FORBIDDEN
        )

    room.is_started = True
    room.save()

    Game.objects.create(
        room=room,
        current_turn=host
    )

    # 🔔 WebSocket: game started
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'game_started'
        }
    )

    return Response(
        {'status': 'game_started'},
        status=status.HTTP_200_OK
    )


# =========================
# ROLL DICE (TURN-BASED)
# =========================

@api_view(['POST'])
def roll_dice(request):
    game_id = request.data.get('game_id')
    player_id = request.data.get('player_id')

    if not game_id or not player_id:
        return Response(
            {'error': 'game_id and player_id required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        game = Game.objects.get(id=game_id)
    except Game.DoesNotExist:
        return Response(
            {'error': 'Game not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    if game.current_turn.id != player_id:
        return Response(
            {'error': 'Not your turn'},
            status=status.HTTP_403_FORBIDDEN
        )

    dice = random.randint(1, 6)
    game.last_dice = dice

    players = list(game.room.players.all())
    current_index = players.index(game.current_turn)
    next_index = (current_index + 1) % len(players)
    game.current_turn = players[next_index]

    game.save()

    # 🔔 WebSocket: dice rolled
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'lobby_{game.room.code}',
        {
            'type': 'dice_rolled',
            'dice': dice,
            'next_player_id': game.current_turn.id
        }
    )

    return Response(
        {
            'dice': dice,
            'next_player_id': game.current_turn.id
        },
        status=status.HTTP_200_OK
    )
