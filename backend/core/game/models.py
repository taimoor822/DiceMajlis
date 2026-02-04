from django.db import models
import uuid


class Room(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    code = models.CharField(max_length=6, unique=True)
    max_players = models.PositiveIntegerField(default=4)
    is_started = models.BooleanField(default=False)
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
    joined_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.name


class Game(models.Model):
    room = models.OneToOneField(
        Room,
        related_name='game',
        on_delete=models.CASCADE
    )

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

    def __str__(self):
        return f"Game in room {self.room.code}"
    

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
