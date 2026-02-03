
import random
import string

from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from .game_logic import is_valid_move, calculate_new_position

from .models import Room, Player, Game, Token
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
    
    # Create 4 tokens per player
    for player in room.players.all():
        for _ in range(4):
            Token.objects.create(player=player)

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
    room_code = request.data.get('code')
    player_id = request.data.get('player_id')

    if not room_code or not player_id:
        return Response(
            {'error': 'code and player_id required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        room = Room.objects.get(code=room_code)
        game = room.game
        player = Player.objects.get(id=player_id, room=room)
    except:
        return Response({'error': 'Invalid data'}, status=404)

    # ❌ Not your turn
    if game.current_turn != player:
        return Response({'error': 'Not your turn'}, status=403)

    # ❌ Dice already rolled
    if game.last_dice is not None:
        return Response({'error': 'Dice already rolled'}, status=400)

    dice = random.randint(1, 6)
    game.last_dice = dice
    game.save()

    # 🔊 Broadcast dice roll
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'dice_rolled',
            'player_id': str(player.id),
            'dice': dice,
        }
    )

    return Response({'dice': dice})


# =========================
# MOVE TOKEN (AFTER DICE ROLL) 

    
@api_view(['POST'])
def move_token(request):
    """
    Move a token after dice roll
    """

    room_code = request.data.get('code')
    player_id = request.data.get('player_id')
    token_id = request.data.get('token_id')

    if not all([room_code, player_id, token_id]):
        return Response(
            {'error': 'Missing data'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        room = Room.objects.get(code=room_code)
        game = room.game
        player = Player.objects.get(id=player_id, room=room)
        token = Token.objects.get(id=token_id, player=player)
    except:
        return Response({'error': 'Invalid data'}, status=404)

    # ❌ Not your turn
    if game.current_turn != player:
        return Response({'error': 'Not your turn'}, status=403)

    # ❌ No dice rolled
    if game.last_dice is None:
        return Response({'error': 'Roll dice first'}, status=400)

    # ❌ Illegal move
    if not is_valid_move(token, game.last_dice):
        return Response({'error': 'Invalid move'}, status=400)

    # 🧮 Move token
    old_position = token.position
    new_position = calculate_new_position(token, game.last_dice)

    token.position = new_position
    if new_position == 100:
        token.is_finished = True
    token.save()

    # 💀 Kill logic (enemy tokens at same position)
    killed_tokens = []
    for enemy in Token.objects.filter(
        player__room=room,
        position=new_position
    ).exclude(player=player):

        enemy.position = -1
        enemy.save()
        killed_tokens.append(str(enemy.id))

    channel_layer = get_channel_layer()

    # 🔊 Broadcast token movement
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'token_moved',
            'player_id': str(player.id),
            'token_id': str(token.id),
            'from': old_position,
            'to': new_position,
            'dice': game.last_dice,
            'killed': killed_tokens,
        }
    )

    # 🏆 WIN CONDITION
    unfinished_tokens = player.tokens.filter(is_finished=False)
    if not unfinished_tokens.exists():
        game.is_finished = True
        game.save()

        async_to_sync(channel_layer.group_send)(
            f'lobby_{room.code}',
            {
                'type': 'game_finished',
                'winner_id': str(player.id),
            }
        )

        return Response({'winner': True})

    # 🔁 TURN LOGIC
    extra_turn = game.last_dice == 6

    if not extra_turn:
        next_player = get_next_player(room, player)
        game.current_turn = next_player

    # Reset dice AFTER logic
    game.last_dice = None
    game.save()

    # 🔊 Broadcast turn change
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'turn_changed',
            'player_id': str(game.current_turn.id),
        }
    )

    return Response({'success': True})
