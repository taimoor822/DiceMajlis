from rest_framework import serializers

from ludo_engine import MAX_PLAYERS, MIN_PLAYERS, SEAT_COLORS

from .models import Player, Room

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


class CreateRoomInput(serializers.Serializer):
    max_players = serializers.IntegerField(
        min_value=MIN_PLAYERS, max_value=MAX_PLAYERS, default=MAX_PLAYERS
    )
    # Optional: the server picks a free seat colour when it's missing or taken.
    color = serializers.ChoiceField(choices=SEAT_COLORS, required=False)


class RoomInput(serializers.Serializer):
    """A request about one room. Who is asking comes from the sign-in, never the body."""

    code = RoomCodeField()


class JoinRoomInput(RoomInput):
    color = serializers.ChoiceField(choices=SEAT_COLORS, required=False)


class MoveTokenInput(RoomInput):
    token_id = serializers.UUIDField()
