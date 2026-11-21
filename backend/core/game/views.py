"""
Room and game REST API. Every request is checked here before anything changes:
inputs are validated, and every room action needs a signed-in account
(accounts app). Your seat is the one your account holds in that room; the app
never says which player it is. Game state itself only changes through
game.services.

Errors always look like ``{"error": "<message>", "code": "<stable_code>"}``;
the app switches on ``code``.
"""

from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from core.api_errors import invalid_input_response

import game_platform
from game_platform import LUDO

from . import rooms, services
from .models import Game, Player, Room
from .serializers import (
    CreateRoomInput,
    GameChoiceInput,
    JoinRoomInput,
    MoveTokenInput,
    PlayerSerializer,
    RoomInput,
    RoomSerializer,
)
from .tables.ludo import token_ids_by_player

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


# Rule errors from any game's engine, by their stable code.
_RULE_ERROR_HTTP = {
    'not_your_turn': ('Not your turn', status.HTTP_403_FORBIDDEN),
    'unknown_player': ('Player is not in this game', status.HTTP_404_NOT_FOUND),
    'game_not_active': ('Game finished', status.HTTP_400_BAD_REQUEST),
}


def _game_error_response(exc):
    """Engine/service errors -> HTTP. ``code`` is stable for the app to switch on."""
    if isinstance(exc, services.LegacyGame):
        return _error(
            'This game was started before the rules update. Please start a new game.',
            exc.code,
            status.HTTP_409_CONFLICT,
        )
    if isinstance(exc, services.GameConflict):
        return _error('The game changed, please try again', exc.code, status.HTTP_409_CONFLICT)
    if isinstance(exc, services.rule_errors()):
        code = getattr(exc, 'code', 'invalid_action')
        message, http_status = _RULE_ERROR_HTTP.get(code, (str(exc), status.HTTP_400_BAD_REQUEST))
        return _error(message, code, http_status)
    raise exc


def _ludo_only(room):
    """roll-dice and move-token are Ludo's actions (other games act over the socket, 1.12)."""
    if room.game_type != LUDO:
        return _error('This room plays another game', 'wrong_game', status.HTTP_400_BAD_REQUEST)
    return None


def _game_errors():
    return (*services.rule_errors(), services.GameConflict, services.LegacyGame)


def _my_seat(room, user):
    """The seat ``user`` holds in ``room``, or None."""
    return room.players.filter(user=user, is_bot=False).first()


# Room refusals (game/rooms.py) -> HTTP status.
_ROOM_ERROR_HTTP = {
    'room_not_found': status.HTTP_404_NOT_FOUND,
    'not_in_room': status.HTTP_403_FORBIDDEN,
    'not_host': status.HTTP_403_FORBIDDEN,
    'player_kicked': status.HTTP_403_FORBIDDEN,
    'room_locked': status.HTTP_403_FORBIDDEN,
}


def _room_error_response(exc):
    return _error(exc.message, exc.code, _ROOM_ERROR_HTTP.get(exc.code, status.HTTP_400_BAD_REQUEST))


def _seat_response(room, player, http_status):
    return Response(
        {'room': RoomSerializer(room).data, 'player': PlayerSerializer(player).data},
        status=http_status,
    )


# =========================
# ROOM OPTIONS
# =========================

@api_view(['GET'])
def game_catalog(request):
    """Every game and variant the server can run, with their rules (game registry)."""
    return Response({'games': game_platform.catalog()})


@api_view(['GET'])
def room_options(request):
    """
    What the app may offer when creating a room for a game and variant
    (``?game_type=&variant=``, default Ludo Classic), from the rules, not the app.
    """
    form = GameChoiceInput(data=request.query_params)
    if not form.is_valid():
        return _invalid(form)
    variant = form.validated_data['variant_rules']
    return Response({
        'game_type': form.validated_data['game_type'],
        'variant': variant.code,
        'player_counts': list(range(variant.min_players, variant.max_players + 1)),
        'default_player_count': variant.default_players,
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
        room = Room.objects.create(
            code=rooms.new_room_code(),
            game_type=data['game_type'],
            variant=data['variant'],
            max_players=data['max_players'],
        )
        player = Player.objects.create(
            room=room,
            user=user,
            name=user.public_name,
            color=services.color_for_new_player(room, data.get('color')),
            is_host=True,
            is_ready=True,  # the host is always ready
        )
        rooms.settle(room)  # alone and ready: the host may start (the AI joins)

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
        try:
            rooms.check_can_join(room, user)  # started, kicked, locked
        except rooms.RoomError as exc:
            return _room_error_response(exc)
        if room.players.count() >= room.max_players:
            return _error('Room is full', 'room_full', status.HTTP_400_BAD_REQUEST)

        player = Player.objects.create(
            room=room,
            user=user,
            name=user.public_name,
            color=services.color_for_new_player(room, data.get('color')),
            is_host=False,
        )
        room.invites.filter(to_user=user).delete()  # used
        rooms.settle(room)  # a new guest isn't ready yet

    rooms.broadcast_room(room)
    return _seat_response(room, player, status.HTTP_200_OK)


# =========================
# START GAME (HOST ONLY)
# =========================

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def start_game(request):
    """
    The host starts when everyone is ready: a short countdown (STARTING), then
    the game (``game_started`` on the sockets). A host alone gets the Majlis AI.
    """
    form = RoomInput(data=request.data)
    if not form.is_valid():
        return _invalid(form)
    try:
        result = rooms.request_start(request.user, form.validated_data['code'])
    except rooms.RoomError as exc:
        return _room_error_response(exc)
    return Response({'status': 'game_started' if result == 'started' else 'starting'})


# =========================
# INVITES
# =========================

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def invites(request):
    """Invites to rooms you can still join (by Player ID, game/rooms.py)."""
    return Response({'invites': rooms.pending_invites(request.user)})


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
    wrong_game = _ludo_only(room)
    if wrong_game is not None:
        return wrong_game

    try:
        result = services.perform(room.code, {'type': 'roll', 'player_id': str(seat.id)})
    except Game.DoesNotExist:
        return _error('The game has not started', 'game_not_started', status.HTTP_400_BAD_REQUEST)
    except _game_errors() as exc:
        return _game_error_response(exc)

    if result.next_is_bot:
        services.schedule_bots(room.code)

    return Response({
        'dice': result.details.get('dice'),
        'movable_token_ids': list(result.details.get('movable_token_ids', [])),
        'version': result.info.version,
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
    wrong_game = _ludo_only(room)
    if wrong_game is not None:
        return wrong_game
    player_id = str(seat.id)

    my_tokens = token_ids_by_player(room).get(player_id, [])
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
    except _game_errors() as exc:
        return _game_error_response(exc)

    if result.next_is_bot:
        services.schedule_bots(room.code)

    if result.info.finished and result.info.winner_id == player_id:
        return Response({'winner': True, 'version': result.info.version})
    return Response({'success': True, 'version': result.info.version})


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
