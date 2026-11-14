import random
import string

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.core.exceptions import ValidationError
from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from ludo_engine import EngineError, GameNotActive, NotYourTurn, UnknownPlayer

from . import services
from .models import Game, Player, Room, Token
from .serializers import PlayerSerializer, RoomSerializer


# =========================
# UTILS
# =========================

def _error(message, code, http_status):
    return Response({'error': message, 'code': code}, status=http_status)


def _game_error_response(exc):
    """Engine/service errors -> HTTP. ``code`` is stable for the app to switch on."""
    if isinstance(exc, NotYourTurn):
        return _error('Not your turn', exc.code, status.HTTP_403_FORBIDDEN)
    if isinstance(exc, UnknownPlayer):
        return _error('Player is not in this game', exc.code, status.HTTP_404_NOT_FOUND)
    if isinstance(exc, GameNotActive):
        return _error('Game finished', exc.code, status.HTTP_400_BAD_REQUEST)
    if isinstance(exc, services.LegacyGame):
        return _error(
            'This game was started before the rules update. Please start a new game.',
            exc.code,
            status.HTTP_409_CONFLICT,
        )
    if isinstance(exc, services.GameConflict):
        return _error('The game changed, please try again', exc.code, status.HTTP_409_CONFLICT)
    if isinstance(exc, EngineError):
        return _error(str(exc), exc.code, status.HTTP_400_BAD_REQUEST)
    raise exc


def _schedule_ai_turn(room_code: str) -> None:
    """Kept for callers that still import it (e.g. the socket consumer)."""
    services.schedule_bots(room_code)


def generate_room_code():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))


def broadcast_players(room):
    channel_layer = get_channel_layer()

    players = []
    for p in room.players.order_by('joined_at'):
        players.append({
            'id': str(p.id),        # ✅ UUID → string
            'name': p.name,
            'color': p.color,
            'is_host': p.is_host,
            'is_bot': p.is_bot,
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

    with transaction.atomic():
        try:
            room = Room.objects.select_for_update().get(code=code)
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
        except (Player.DoesNotExist, ValidationError, ValueError):
            return Response(
                {'error': 'Only host can start the game'},
                status=status.HTTP_403_FORBIDDEN
            )

        # 🤖 Spawn an AI if the host is alone (v1), sitting opposite the host.
        if (
            room.max_players >= 2
            and room.players.filter(is_bot=False).count() == 1
            and not room.players.filter(is_bot=True).exists()
        ):
            seats = services.assign_seats(list(room.players.order_by('joined_at')))
            ai_seat = services.bot_seat_for(set(seats.values()), seats[str(host.id)])
            Player.objects.create(
                room=room,
                name="Majlis AI",
                color=services.COLOR_BY_SEAT[ai_seat],
                is_host=False,
                is_bot=True,
            )

        room.is_started = True
        room.save()

        game, _state = services.start_game(room, host)

        players_payload = [
            {
                'id': str(p.id),
                'name': p.name,
                'color': p.color,
                'is_host': p.is_host,
                'is_bot': p.is_bot,
            }
            for p in room.players.order_by('joined_at')
        ]

        tokens_payload = [
            {
                'id': str(t.id),
                'player_id': str(t.player_id),
                'position': t.position,
                'is_finished': t.is_finished,
            }
            for t in Token.objects.filter(player__room=room)
            .select_related('player')
            .order_by('created_at')
        ]

    # 🔔 WebSocket: game started (after the transaction committed)
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'game_started',
            'room_code': room.code,
            'current_turn_player_id': str(game.current_turn_id) if game.current_turn_id else None,
            'players': players_payload,
            'tokens': tokens_payload,
            'last_dice': game.last_dice,
            'version': game.version,
            'seconds_left': services.seconds_left(game.turn_deadline),
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
    """The server rolls (SecureDice); the client only asks to roll."""
    room_code = request.data.get('code')
    player_id = request.data.get('player_id')

    if not room_code or not player_id:
        return Response(
            {'error': 'code and player_id required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        result = services.perform(room_code, {'type': 'roll', 'player_id': str(player_id)})
    except (Room.DoesNotExist, Game.DoesNotExist):
        return Response({'error': 'Invalid data'}, status=status.HTTP_404_NOT_FOUND)
    except (EngineError, services.GameConflict, services.LegacyGame) as exc:
        return _game_error_response(exc)

    if result.next_is_bot:
        services.schedule_bots(room_code)

    return Response({'dice': result.dice, 'version': result.state.version})


# =========================
# MOVE TOKEN (AFTER DICE ROLL)
# =========================

@api_view(['POST'])
def move_token(request):
    """Move one of your tokens by the rolled value. The engine decides if it's legal."""
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
    except Room.DoesNotExist:
        return Response({'error': 'Invalid data'}, status=status.HTTP_404_NOT_FOUND)

    my_tokens = services.token_ids_by_player(room).get(str(player_id), [])
    if str(token_id) not in my_tokens:
        return Response({'error': 'Invalid data'}, status=status.HTTP_404_NOT_FOUND)

    try:
        result = services.perform(room_code, {
            'type': 'move',
            'player_id': str(player_id),
            'token_index': my_tokens.index(str(token_id)),
        })
    except Game.DoesNotExist:
        return Response({'error': 'Invalid data'}, status=status.HTTP_404_NOT_FOUND)
    except (EngineError, services.GameConflict, services.LegacyGame) as exc:
        return _game_error_response(exc)

    if result.next_is_bot:
        services.schedule_bots(room_code)

    if result.state.is_finished and result.state.winner_id == str(player_id):
        return Response({'winner': True, 'version': result.state.version})
    return Response({'success': True, 'version': result.state.version})
