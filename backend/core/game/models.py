from django.conf import settings
from django.db import models
from django.db.models import Q
import uuid

from game_platform import CLASSIC, LUDO

# Which game and which way to play it (game_platform registry). Plain text, not
# choices: the registry decides what exists, and the views check it.
GAME_TYPE_MAX_LENGTH = 20
VARIANT_MAX_LENGTH = 30


class Room(models.Model):
    """
    A private room (PLATFORM.md §5): WAITING → READY → STARTING → PLAYING →
    FINISHED → CLOSED. Its rules live in game/rooms.py.
    """

    class Status(models.TextChoices):
        WAITING = 'waiting'  # someone isn't ready yet
        READY = 'ready'  # everyone is ready: the host may start
        STARTING = 'starting'  # the countdown runs (``starts_at``)
        PLAYING = 'playing'
        FINISHED = 'finished'  # game over; players may ask for a rematch
        CLOSED = 'closed'  # everyone left, or the rematch moved to ``next_room``

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    code = models.CharField(max_length=6, unique=True)
    game_type = models.CharField(max_length=GAME_TYPE_MAX_LENGTH, default=LUDO)
    variant = models.CharField(max_length=VARIANT_MAX_LENGTH, default=CLASSIC)
    max_players = models.PositiveIntegerField(default=4)
    is_started = models.BooleanField(default=False)
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.WAITING, db_index=True
    )
    # Locked: only people with an invite may join.
    is_locked = models.BooleanField(default=False)
    # The host's custom rules (checked against the variant's options).
    options = models.JSONField(default=dict, blank=True)
    # End of the start countdown (status STARTING).
    starts_at = models.DateTimeField(null=True, blank=True, db_index=True)
    # Removed by the host: they may not come back to this room.
    kicked_users = models.ManyToManyField(
        settings.AUTH_USER_MODEL, related_name='+', blank=True
    )
    # Where the rematch is played.
    next_room = models.ForeignKey(
        'self', null=True, blank=True, on_delete=models.SET_NULL, related_name='+'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Room {self.code}"


class Player(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    room = models.ForeignKey(Room, related_name='players', on_delete=models.CASCADE)
    name = models.CharField(max_length=30)
    color = models.CharField(max_length=20)
    position = models.IntegerField(default=0)
    is_host = models.BooleanField(default=False)
    is_bot = models.BooleanField(default=False)
    # Before the start: ready to play (the host always is).
    is_ready = models.BooleanField(default=False)
    # After the game: wants to play again with the same people.
    wants_rematch = models.BooleanField(default=False)
    # Left the room after the start (forfeited, or went home after the game).
    has_left = models.BooleanField(default=False)
    joined_at = models.DateTimeField(auto_now_add=True)
    # The account sitting here. NULL for bots (and if an account is ever deleted,
    # so the game history stays intact).
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name='seats',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )

    class Meta:
        constraints = [
            # One seat per account in a room.
            models.UniqueConstraint(
                fields=['room', 'user'],
                condition=Q(user__isnull=False),
                name='unique_seat_per_user',
            ),
        ]

    def __str__(self):
        return self.name


class Game(models.Model):
    room = models.OneToOneField(
        Room,
        related_name='game',
        on_delete=models.CASCADE
    )

    # Copied from the room when the game starts; decides which engine runs it.
    game_type = models.CharField(max_length=GAME_TYPE_MAX_LENGTH, default=LUDO)
    variant = models.CharField(max_length=VARIANT_MAX_LENGTH, default=CLASSIC)

    current_turn = models.ForeignKey(
        Player,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='current_games'
    )

    current_turn_index = models.IntegerField(default=0)

    last_dice = models.IntegerField(null=True, blank=True)

    is_finished = models.BooleanField(default=False)

    # Authoritative engine snapshot (the game's ``dump()``; for Ludo
    # GameState.to_dict()). current_turn, is_finished and, for Ludo, last_dice
    # and the Token rows are mirrors of it for existing reads.
    # Only game.services may write these. NULL = game started before the engine.
    state = models.JSONField(null=True, blank=True)
    initial_state = models.JSONField(null=True, blank=True)
    version = models.PositiveIntegerField(default=0)

    # When the current turn runs out. Written in the same transaction as
    # ``state`` so the two can never disagree. NULL = no timer (game over).
    turn_deadline = models.DateTimeField(null=True, blank=True, db_index=True)

    def __str__(self):
        return f"Game in room {self.room.code}"


class GameAction(models.Model):
    """
    Every accepted action, in order, including the server's dice value.
    The game's ``replay(initial_state, actions)`` rebuilds it exactly:
    used for disputes, anti-cheat review and recovery.
    """

    game = models.ForeignKey(Game, related_name='actions', on_delete=models.CASCADE)
    version = models.PositiveIntegerField()
    action = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['version']
        constraints = [
            models.UniqueConstraint(fields=['game', 'version'], name='unique_game_action_version'),
        ]

    def __str__(self):
        return f"{self.game} v{self.version}: {self.action.get('type')}"
    

class Token(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    player = models.ForeignKey(
        Player,
        related_name='tokens',
        on_delete=models.CASCADE
    )

    position = models.IntegerField(default=-1)
    # -1 = home
    # 0+ = path index
    # 100 = finished (home end)

    is_finished = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Token {self.id} ({self.player.name}) @ {self.position}"



class RoomInvite(models.Model):
    """An invite to a room by Player ID. Lets the guest into a locked room."""

    room = models.ForeignKey(Room, related_name='invites', on_delete=models.CASCADE)
    from_user = models.ForeignKey(
        settings.AUTH_USER_MODEL, related_name='+', on_delete=models.CASCADE
    )
    to_user = models.ForeignKey(
        settings.AUTH_USER_MODEL, related_name='room_invites', on_delete=models.CASCADE
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['room', 'to_user'], name='unique_room_invite'),
        ]

    def __str__(self):
        return f"Invite to {self.room.code}"


class Turn(models.Model):
    game = models.ForeignKey(
        Game,
        related_name='turns',
        on_delete=models.CASCADE
    )
    player = models.ForeignKey(Player, on_delete=models.CASCADE)
    dice_value = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.player.name} rolled {self.dice_value}"
