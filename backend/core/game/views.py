"""
Room and game REST API. Every request is checked here before anything changes:
inputs are validated, and seat actions (start, roll, move) need the player's
seat secret (see game.player_auth). Game state itself only changes through
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
from rest_framework.decorators import api_view
from rest_framework.response import Response

from ludo_engine import (
    MAX_PLAYERS,
    MIN_PLAYERS,
    EngineError,
    GameNotActive,
    NotYourTurn,
    UnknownPlayer,
)

from . import player_auth, services
from .models import Game, Player, Room
from .serializers import (
    CreateRoomInput,
    JoinRoomInput,
    MoveTokenInput,
    PlayerSerializer,
    RoomSerializer,
    SeatInput,
)

ROOM_CODE_LENGTH = 4
ROOM_CODE_ALPHABET = string.ascii_uppercase + string.digits


# =========================
# HELPERS
# =========================

def _error(message, code, http_status):
    return Response({'error': message, 'code': code}, status=http_status)


def _invalid(serializer):
    return Response(
        {'error': 'Invalid request', 'code': 'invalid_input', 'fields': serializer.errors},
        status=status.HTTP_400_BAD_REQUEST,
    )


def _room_not_found():
    return _error('Room not found', 'room_not_found', status.HTTP_404_NOT_FOUND)


def _not_your_seat():
    return _error('This seat belongs to someone else', 'not_your_seat', status.HTTP_403_FORBIDDEN)


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


def _seat_owner(room, player_id, secret):
    """The human player at ``player_id`` in ``room`` if ``secret`` is theirs, else None."""
    player = Player.objects.filter(id=player_id, room=room, is_bot=False).first()
    if player is None or not player_auth.owns_seat(player, secret):
        return None
    return player


def generate_room_code():
    return ''.join(secrets.choice(ROOM_CODE_ALPHABET) for _ in range(ROOM_CODE_LENGTH))


def broadcast_players(room):
    async_to_sync(get_channel_layer().group_send)(
        services.group_name(room.code),
        {'type': 'players_updated', 'players': services.players_payload(room)},
    )


def _joined_response(room, player, secret, http_status):
    return Response(
        {
            'room': RoomSerializer(room).data,
            'player': PlayerSerializer(player).data,
            # Only this device gets it. Send it back with start / roll / move.
            'player_token': secret,
        },
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
def create_room(request):
    form = CreateRoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data

    with transaction.atomic():
        code = generate_room_code()
        while Room.objects.filter(code=code).exists():
            code = generate_room_code()
        room = Room.objects.create(code=code, max_players=data['max_players'])
        player = Player.objects.create(
            room=room,
            name=data.get('name') or services.default_player_name(room),
            color=services.color_for_new_player(room, data.get('color')),
            is_host=True,
        )
        secret = player_auth.issue_secret(player)

    return _joined_response(room, player, secret, status.HTTP_201_CREATED)


# =========================
# JOIN ROOM
# =========================

@api_view(['POST'])
def join_room(request):
    form = JoinRoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data

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
            name=data.get('name') or services.default_player_name(room),
            color=services.color_for_new_player(room, data.get('color')),
            is_host=False,
        )
        secret = player_auth.issue_secret(player)

    broadcast_players(room)
    return _joined_response(room, player, secret, status.HTTP_200_OK)


# =========================
# START GAME (HOST ONLY)
# =========================

@api_view(['POST'])
def start_game(request):
    form = SeatInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data

    with transaction.atomic():
        room = Room.objects.select_for_update().filter(code=data['code']).first()
        if room is None:
            return _room_not_found()
        host = _seat_owner(room, data['player_id'], data['player_token'])
        if host is None:
            return _not_your_seat()
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
def roll_dice(request):
    """The server rolls (SecureDice); the client only asks to roll."""
    form = SeatInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data

    room = Room.objects.filter(code=data['code']).first()
    if room is None:
        return _room_not_found()
    if _seat_owner(room, data['player_id'], data['player_token']) is None:
        return _not_your_seat()

    try:
        result = services.perform(room.code, {'type': 'roll', 'player_id': str(data['player_id'])})
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
def move_token(request):
    """Move one of your tokens by the rolled value. The engine decides if it's legal."""
    form = MoveTokenInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    data = form.validated_data
    player_id, token_id = str(data['player_id']), str(data['token_id'])

    room = Room.objects.filter(code=data['code']).first()
    if room is None:
        return _room_not_found()
    if _seat_owner(room, player_id, data['player_token']) is None:
        return _not_your_seat()

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
