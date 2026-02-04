
import random
import string
import threading
import time

from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from django.db import close_old_connections

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from .utils import (
    FINISH_POSITION,
    SAFE_ZONES,
    calculate_new_position,
    get_next_player,
    is_valid_move,
    kill_enemy_tokens,
)

from .models import Room, Player, Game, Token
from .serializers import RoomSerializer, PlayerSerializer


# =========================
# UTILS
# =========================

_AI_LOCK = threading.Lock()
_AI_ACTIVE_ROOMS: set[str] = set()


def _schedule_ai_turn(room_code: str) -> None:
    """
    Fire-and-forget AI turn runner (dev-friendly).
    Keeps the game server-authoritative; clients only react to WS events.
    """
    with _AI_LOCK:
        if room_code in _AI_ACTIVE_ROOMS:
            return
        _AI_ACTIVE_ROOMS.add(room_code)

    threading.Thread(
        target=_run_ai_loop,
        args=(room_code,),
        daemon=True,
    ).start()


def _run_ai_loop(room_code: str) -> None:
    """
    Executes AI rolls/moves until the turn leaves the bot or the game ends.
    Uses the same DB + WS events as humans (dice_rolled, token_moved, turn_changed, game_finished).
    """
    close_old_connections()
    try:
        channel_layer = get_channel_layer()

        max_actions = 200
        actions = 0

        while actions < max_actions:
            actions += 1

            try:
                room = Room.objects.get(code=room_code)
                game = room.game
            except Exception:
                return

            if not room.is_started or game.is_finished:
                return

            bot = game.current_turn
            if bot is None or not getattr(bot, "is_bot", False):
                return

            # Roll if needed
            if game.last_dice is None:
                time.sleep(random.uniform(0.7, 1.4))

                # Re-check before acting
                room = Room.objects.get(code=room_code)
                game = room.game
                bot = game.current_turn
                if bot is None or not getattr(bot, "is_bot", False) or game.is_finished:
                    return

                dice = random.randint(1, 6)
                game.last_dice = dice
                game.save(update_fields=["last_dice"])

                async_to_sync(channel_layer.group_send)(
                    f"lobby_{room.code}",
                    {
                        "type": "dice_rolled",
                        "player_id": str(bot.id),
                        "dice": dice,
                    },
                )

            # Move after a roll
            dice_value = game.last_dice
            if dice_value is None:
                continue

            tokens = list(Token.objects.filter(player=bot, is_finished=False).order_by("created_at"))
            valid_tokens = [t for t in tokens if is_valid_move(t, dice_value)]

            if not valid_tokens:
                # Auto-skip if no valid moves
                next_player = get_next_player(room, bot)
                game.last_dice = None
                if next_player is not None:
                    game.current_turn = next_player
                game.save(update_fields=["current_turn", "last_dice"])

                async_to_sync(channel_layer.group_send)(
                    f"lobby_{room.code}",
                    {
                        "type": "turn_changed",
                        "player_id": str(game.current_turn.id) if game.current_turn else None,
                    },
                )
                continue

            # Small delay to feel human-like (and to let clients animate dice)
            time.sleep(random.uniform(0.4, 0.9))

            # Choose a token:
            # - Prefer finishing moves
            # - Prefer kills
            # - Otherwise prefer furthest progress
            best_token = valid_tokens[0]
            best_score = -10_000

            for t in valid_tokens:
                new_pos = calculate_new_position(t, dice_value)
                finishes = new_pos == FINISH_POSITION
                can_kill = new_pos not in SAFE_ZONES and (
                    Token.objects.filter(player__room=room, position=new_pos)
                    .exclude(player=bot)
                    .exists()
                )
                score = new_pos
                if can_kill:
                    score += 500
                if finishes:
                    score += 1000
                if score > best_score:
                    best_score = score
                    best_token = t

            old_position = best_token.position
            new_position = calculate_new_position(best_token, dice_value)

            best_token.position = new_position
            if new_position == FINISH_POSITION:
                best_token.is_finished = True
            best_token.save(update_fields=["position", "is_finished"])

            killed_tokens = kill_enemy_tokens(
                room=room,
                moving_player=bot,
                position=new_position,
            )

            async_to_sync(channel_layer.group_send)(
                f"lobby_{room.code}",
                {
                    "type": "token_moved",
                    "player_id": str(bot.id),
                    "token_id": str(best_token.id),
                    "from": old_position,
                    "to": new_position,
                    "dice": dice_value,
                    "killed": killed_tokens,
                },
            )

            # Win check
            if not bot.tokens.filter(is_finished=False).exists():
                game.is_finished = True
                game.save(update_fields=["is_finished"])

                async_to_sync(channel_layer.group_send)(
                    f"lobby_{room.code}",
                    {
                        "type": "game_finished",
                        "winner_id": str(bot.id),
                    },
                )
                return

            extra_turn = dice_value == 6
            if not extra_turn:
                next_player = get_next_player(room, bot)
                if next_player is not None:
                    game.current_turn = next_player

            game.last_dice = None
            game.save(update_fields=["current_turn", "last_dice"])

            async_to_sync(channel_layer.group_send)(
                f"lobby_{room.code}",
                {
                    "type": "turn_changed",
                    "player_id": str(game.current_turn.id) if game.current_turn else None,
                },
            )

            # If it stays AI (extra turn), loop continues and will roll again.
    finally:
        with _AI_LOCK:
            _AI_ACTIVE_ROOMS.discard(room_code)
        close_old_connections()


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

    # 🤖 Spawn an AI if the host is alone (v1).
    # This keeps "2 player" gameplay always possible without changing APIs.
    if (
        room.max_players >= 2
        and room.players.filter(is_bot=False).count() == 1
        and not room.players.filter(is_bot=True).exists()
    ):
        used_colors = set(room.players.values_list("color", flat=True))
        ai_color = next((c for c in ["blue", "green", "orange"] if c not in used_colors), "blue")
        Player.objects.create(
            room=room,
            name="Majlis AI",
            color=ai_color,
            is_host=False,
            is_bot=True,
        )

    room.is_started = True
    room.save()

    game = Game.objects.create(
        room=room,
        current_turn=host
    )
    
    # Create 4 tokens per player
    for player in room.players.order_by('joined_at'):
        for _ in range(4):
            Token.objects.create(player=player)

    # 🔔 WebSocket: game started
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

    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'game_started',
            'room_code': room.code,
            'current_turn_player_id': str(game.current_turn.id) if game.current_turn else None,
            'players': players_payload,
            'tokens': tokens_payload,
            'last_dice': game.last_dice,
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

    if game.is_finished:
        return Response({'error': 'Game finished'}, status=400)

    # Turn enforcement (server-authoritative)
    if game.current_turn != player:
        return Response({'error': 'Not your turn'}, status=403)

    # Only one roll is allowed until a token is moved (prevents re-rolling)
    if game.last_dice is not None:
        return Response({'error': 'Dice already rolled'}, status=400)

    dice = random.randint(1, 6)
    game.last_dice = dice
    game.save(update_fields=['last_dice'])

    # 🔊 Broadcast dice roll (clients must render server value only)
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'dice_rolled',
            'player_id': str(player.id),
            'dice': dice,
        }
    )

    # If the player has no legal moves for this dice, auto-pass to avoid deadlocks.
    unfinished_tokens = Token.objects.filter(player=player, is_finished=False)
    if not unfinished_tokens.exists():
        game.is_finished = True
        game.save(update_fields=['is_finished'])

        async_to_sync(channel_layer.group_send)(
            f'lobby_{room.code}',
            {
                'type': 'game_finished',
                'winner_id': str(player.id),
            }
        )
        return Response({'dice': dice})

    has_any_move = any(is_valid_move(t, dice) for t in unfinished_tokens)
    if not has_any_move:
        next_player = get_next_player(room, player)
        game.last_dice = None
        if next_player is not None:
            game.current_turn = next_player
        game.save(update_fields=['current_turn', 'last_dice'])

        async_to_sync(channel_layer.group_send)(
            f'lobby_{room.code}',
            {
                'type': 'turn_changed',
                'player_id': str(game.current_turn.id) if game.current_turn else None,
            }
        )
        if game.current_turn is not None and getattr(game.current_turn, "is_bot", False):
            _schedule_ai_turn(room.code)

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

    if game.is_finished:
        return Response({'error': 'Game finished'}, status=400)

    # Turn enforcement (server-authoritative)
    if game.current_turn != player:
        return Response({'error': 'Not your turn'}, status=403)

    # A move is only allowed after a roll (dice value is stored on Game)
    if game.last_dice is None:
        return Response({'error': 'Roll dice first'}, status=400)

    # Validate move using strict v1 rules (home exit on 6, no overshoot past 100)
    if not is_valid_move(token, game.last_dice):
        return Response({'error': 'Invalid move'}, status=400)

    # 🧮 Move token
    old_position = token.position
    new_position = calculate_new_position(token, game.last_dice)

    token.position = new_position
    if new_position == FINISH_POSITION:
        token.is_finished = True
    token.save(update_fields=['position', 'is_finished'])

    # 💀 Kill logic: landing on enemy token sends it back to home (-1)
    killed_tokens = kill_enemy_tokens(
        room=room,
        moving_player=player,
        position=new_position,
    )

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

    # 🏆 WIN CONDITION: all 4 tokens finished
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

    # 🔁 TURN LOGIC: 6 grants extra turn, otherwise pass to next player
    extra_turn = game.last_dice == 6

    if not extra_turn:
        next_player = get_next_player(room, player)
        if next_player is not None:
            game.current_turn = next_player

    # Reset dice AFTER logic
    game.last_dice = None
    game.save(update_fields=['current_turn', 'last_dice'])

    # 🔊 Broadcast turn (always, even if extra turn keeps same player)
    async_to_sync(channel_layer.group_send)(
        f'lobby_{room.code}',
        {
            'type': 'turn_changed',
            'player_id': str(game.current_turn.id) if game.current_turn else None,
        }
    )
    if game.current_turn is not None and getattr(game.current_turn, "is_bot", False):
        _schedule_ai_turn(room.code)

    return Response({'success': True})
