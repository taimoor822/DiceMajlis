from rest_framework import serializers

from ludo_engine import MAX_PLAYERS, MIN_PLAYERS, SEAT_COLORS

from .models import Player, Room

NAME_MAX_LENGTH = Player._meta.get_field('name').max_length
CODE_MAX_LENGTH = Room._meta.get_field('code').max_length


class RoomSerializer(serializers.ModelSerializer):
    class Meta:
        model = Room
        fields = ['id', 'code', 'max_players', 'is_started']


class PlayerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Player
        fields = ['id', 'name', 'color', 'is_host', 'is_bot']


# ---------------------------------------------------------------------------
# Request input. The server checks everything the app sends.
# ---------------------------------------------------------------------------


class RoomCodeField(serializers.CharField):
    """Room codes are upper-case; accept any case and surrounding spaces."""

    def __init__(self, **kwargs):
        kwargs.setdefault('max_length', CODE_MAX_LENGTH)
        super().__init__(**kwargs)

    def to_internal_value(self, data):
        return super().to_internal_value(data).upper()


class _PlayerDetailsInput(serializers.Serializer):
    # Optional: the server picks a name and a free seat colour when they're missing.
    name = serializers.CharField(max_length=NAME_MAX_LENGTH, required=False, allow_blank=True)
    color = serializers.ChoiceField(choices=SEAT_COLORS, required=False)


class CreateRoomInput(_PlayerDetailsInput):
    max_players = serializers.IntegerField(
        min_value=MIN_PLAYERS, max_value=MAX_PLAYERS, default=MAX_PLAYERS
    )


class JoinRoomInput(_PlayerDetailsInput):
    code = RoomCodeField()


class SeatInput(serializers.Serializer):
    """A request made from a seat: who is asking, and the secret proving it."""

    code = RoomCodeField()
    player_id = serializers.UUIDField()
    player_token = serializers.CharField(max_length=128)


class MoveTokenInput(SeatInput):
    token_id = serializers.UUIDField()
