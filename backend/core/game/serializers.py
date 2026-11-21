from rest_framework import serializers

import game_platform
from game_platform import LUDO
from ludo_engine import SEAT_COLORS

from .models import GAME_TYPE_MAX_LENGTH, VARIANT_MAX_LENGTH, Player, Room

CODE_MAX_LENGTH = Room._meta.get_field('code').max_length


class RoomSerializer(serializers.ModelSerializer):
    class Meta:
        model = Room
        fields = ['id', 'code', 'game_type', 'variant', 'max_players', 'is_started']


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


class GameChoiceInput(serializers.Serializer):
    """Which game and variant (from the game registry). Both optional: Ludo, its default variant."""

    game_type = serializers.CharField(max_length=GAME_TYPE_MAX_LENGTH, default=LUDO)
    variant = serializers.CharField(max_length=VARIANT_MAX_LENGTH, required=False, allow_blank=True)

    def validate(self, data):
        try:
            game_platform.get_game(data['game_type'])
        except game_platform.UnknownGame:
            raise serializers.ValidationError({'game_type': 'No such game'}, code='unknown_game')
        try:
            variant = game_platform.get_variant(data['game_type'], data.get('variant') or None)
        except game_platform.UnknownVariant:
            raise serializers.ValidationError({'variant': 'No such variant'}, code='unknown_variant')
        data['variant'] = variant.code
        data['variant_rules'] = variant
        return data


class CreateRoomInput(GameChoiceInput):
    # Seats in the room; the variant decides what is allowed (and the default).
    max_players = serializers.IntegerField(required=False)
    # Optional: the server picks a free seat colour when it's missing or taken.
    color = serializers.ChoiceField(choices=SEAT_COLORS, required=False)

    def validate(self, data):
        data = super().validate(data)
        variant = data.pop('variant_rules')
        count = data.setdefault('max_players', variant.default_players)
        if count < variant.min_players:
            raise serializers.ValidationError({'max_players': 'Too few seats'}, code='min_value')
        if count > variant.max_players:
            raise serializers.ValidationError({'max_players': 'Too many seats'}, code='max_value')
        return data


class RoomInput(serializers.Serializer):
    """A request about one room. Who is asking comes from the sign-in, never the body."""

    code = RoomCodeField()


class JoinRoomInput(RoomInput):
    color = serializers.ChoiceField(choices=SEAT_COLORS, required=False)


class MoveTokenInput(RoomInput):
    token_id = serializers.UUIDField()
