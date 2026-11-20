"""
Room and game REST API. Every request is checked here before anything changes:
inputs are validated, and every room action needs a signed-in account
(accounts app). Your seat is the one your account holds in that room; the app
never says which player it is. Game state itself only changes through
game.services.

Errors always look like ``{"error": "<message>", "code": "<stable_code>"}``;
the app switches on ``code``.
"""

import secrets
import string

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.api_errors import invalid_input_response

from ludo_engine import (
    MAX_PLAYERS,
    MIN_PLAYERS,
    EngineError,
    GameNotActive,
    NotYourTurn,
    UnknownPlayer,
)

from . import services
from .models import Game, Player, Room
from .serializers import (
    CreateRoomInput,
    JoinRoomInput,
    MoveTokenInput,
    PlayerSerializer,
    RoomInput,
    RoomSerializer,
)

ROOM_CODE_LENGTH = 4
ROOM_CODE_ALPHABET = string.ascii_uppercase + string.digits


# =========================
# HELPERS
# =========================

def _error(message, code, http_status):
    return Response({'error': message, 'code': code}, status=http_status)


def _invalid(serializer):
    return invalid_input_response(serializer)


def _room_not_found():
    return _error('Room not found', 'room_not_found', status.HTTP_404_NOT_FOUND)


def _not_in_room():
    return _error('You are not in this room', 'not_in_room', status.HTTP_403_FORBIDDEN)


def _already_in_game(room):
    return Response(
        {
            'error': 'You are still playing another game',
            'code': 'already_in_game',
            'room_code': room.code,
        },
        status=status.HTTP_409_CONFLICT,
    )


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


def _my_seat(room, user):
    """The seat ``user`` holds in ``room``, or None."""
    return room.players.filter(user=user, is_bot=False).first()


def generate_room_code():
    return ''.join(secrets.choice(ROOM_CODE_ALPHABET) for _ in range(ROOM_CODE_LENGTH))


def _seat_response(room, player, http_status):
    return Response(
        {'room': RoomSerializer(room).data, 'player': PlayerSerializer(player).data},
        status=http_status,
    )


# =========================
# ROOM OPTIONS
# =========================

@api_view(['GET'])
def room_options(request):
    """What the app may offer when creating a room (from the rules, not the app)."""
    return Response({
        'player_counts': list(range(MIN_PLAYERS, MAX_PLAYERS + 1)),
        'default_player_count': MAX_PLAYERS,
    })


# =========================
# CREATE ROOM
# =========================

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def create_room(request):
    form = CreateRoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    user = request.user

    # One game at a time; an older room you were only waiting in is left for you.
    playing = services.game_in_progress_for(user)
    if playing is not None:
        return _already_in_game(playing)
    services.leave_waiting_rooms(user)

    with transaction.atomic():
        code = generate_room_code()
        while Room.objects.filter(code=code).exists():
            code = generate_room_code()
        room = Room.objects.create(code=code, max_players=data['max_players'])
        player = Player.objects.create(
            room=room,
            user=user,
            name=user.public_name,
            color=services.color_for_new_player(room, data.get('color')),
            is_host=True,
        )

    return _seat_response(room, player, status.HTTP_201_CREATED)


# =========================
# JOIN ROOM
# =========================

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def join_room(request):
    """Take a seat. Joining a room you are already in just returns your seat."""
    form = JoinRoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    user = request.user

    room = Room.objects.filter(code=data['code']).first()
    if room is None:
        return _room_not_found()
    seat = _my_seat(room, user)
    if seat is not None:
        return _seat_response(room, seat, status.HTTP_200_OK)

    playing = services.game_in_progress_for(user, exclude_room=room)
    if playing is not None:
        return _already_in_game(playing)
    services.leave_waiting_rooms(user, keep=room)

    with transaction.atomic():
        # Locked so two people can't take the last seat at the same moment.
        room = Room.objects.select_for_update().filter(code=data['code']).first()
        if room is None:
            return _room_not_found()
        if room.is_started:
            return _error('Game already started', 'game_already_started', status.HTTP_400_BAD_REQUEST)
        if room.players.count() >= room.max_players:
            return _error('Room is full', 'room_full', status.HTTP_400_BAD_REQUEST)

        player = Player.objects.create(
            room=room,
            user=user,
            name=user.public_name,
            color=services.color_for_new_player(room, data.get('color')),
            is_host=False,
        )

    services.broadcast_players(room)
    return _seat_response(room, player, status.HTTP_200_OK)


# =========================
# START GAME (HOST ONLY)
# =========================

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def start_game(request):
    form = RoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data

    with transaction.atomic():
        room = Room.objects.select_for_update().filter(code=data['code']).first()
        if room is None:
            return _room_not_found()
        host = _my_seat(room, request.user)
        if host is None:
            return _not_in_room()
        if not host.is_host:
            return _error('Only the host can start the game', 'not_host', status.HTTP_403_FORBIDDEN)
        if room.is_started:
            return _error('Game already started', 'game_already_started', status.HTTP_400_BAD_REQUEST)

        # Spawn an AI if the host is alone (v1), sitting opposite the host.
        if (
            room.players.filter(is_bot=False).count() == 1
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
        room.save(update_fields=['is_started'])
        try:
            services.start_game(room, host)
        except EngineError as exc:
            transaction.set_rollback(True)
            return _game_error_response(exc)
        snapshot = services.game_snapshot(room)

    # WebSocket: game started (after the transaction committed)
    async_to_sync(get_channel_layer().group_send)(services.group_name(room.code), snapshot)

    return Response({'status': 'game_started'}, status=status.HTTP_200_OK)


# =========================
# ROLL DICE (TURN-BASED)
# =========================

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def roll_dice(request):
    """The server rolls (SecureDice); the client only asks to roll."""
    form = RoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data

    room = Room.objects.filter(code=data['code']).first()
    if room is None:
        return _room_not_found()
    seat = _my_seat(room, request.user)
    if seat is None:
        return _not_in_room()

    try:
        result = services.perform(room.code, {'type': 'roll', 'player_id': str(seat.id)})
    except Game.DoesNotExist:
        return _error('The game has not started', 'game_not_started', status.HTTP_400_BAD_REQUEST)
    except (EngineError, services.GameConflict, services.LegacyGame) as exc:
        return _game_error_response(exc)

    if result.next_is_bot:
        services.schedule_bots(room.code)

    return Response({
        'dice': result.dice,
        'movable_token_ids': list(result.movable_token_ids),
        'version': result.state.version,
    })


# =========================
# MOVE TOKEN (AFTER DICE ROLL)
# =========================

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def move_token(request):
    """Move one of your tokens by the rolled value. The engine decides if it's legal."""
    form = MoveTokenInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    token_id = str(data['token_id'])

    room = Room.objects.filter(code=data['code']).first()
    if room is None:
        return _room_not_found()
    seat = _my_seat(room, request.user)
    if seat is None:
        return _not_in_room()
    player_id = str(seat.id)

    my_tokens = services.token_ids_by_player(room).get(player_id, [])
    if token_id not in my_tokens:
        return _error('That token is not yours', 'not_your_token', status.HTTP_404_NOT_FOUND)

    try:
        result = services.perform(room.code, {
            'type': 'move',
            'player_id': player_id,
            'token_index': my_tokens.index(token_id),
        })
    except Game.DoesNotExist:
        return _error('The game has not started', 'game_not_started', status.HTTP_400_BAD_REQUEST)
    except (EngineError, services.GameConflict, services.LegacyGame) as exc:
        return _game_error_response(exc)

    if result.next_is_bot:
        services.schedule_bots(room.code)

    if result.state.is_finished and result.state.winner_id == player_id:
        return Response({'winner': True, 'version': result.state.version})
    return Response({'success': True, 'version': result.state.version})


# =========================
# LEAVE ROOM
# =========================

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def leave_room(request):
    """
    Leave a room. Before the start your seat is freed (the host role passes on);
    during a game you forfeit. Leaving a room you are not in is not an error.
    """
    form = RoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)

    room = Room.objects.filter(code=form.validated_data['code']).first()
    seat = _my_seat(room, request.user) if room is not None else None
    if seat is not None:
        try:
            services.leave_room(seat)
        except services.GameConflict as exc:
            return _game_error_response(exc)
    return Response({'status': 'left'})
