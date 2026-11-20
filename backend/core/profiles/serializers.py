import re
import unicodedata

from rest_framework import serializers

from . import choices
from .countries import COUNTRY_CODES

_SPACES = re.compile(r"\s+")
# Allowed besides letters, combining marks (Arabic/Urdu vowel signs) and digits.
_EXTRA_CHARACTERS = set(" _-.'")


def clean_display_name(value: str) -> str:
    """
    Trim, collapse spaces, then check the name. Letters from any script, digits,
    spaces and _ - . ' are allowed; emoji, symbols and invisible characters aren't.
    Raises ValidationError with a stable code.
    """
    name = _SPACES.sub(" ", unicodedata.normalize("NFC", value)).strip()
    if not choices.NAME_MIN_LENGTH <= len(name) <= choices.NAME_MAX_LENGTH:
        raise serializers.ValidationError("Name must be 2–20 characters.", code="name_length")
    for character in name:
        kind = unicodedata.category(character)[0]
        if kind not in ("L", "M", "N") and character not in _EXTRA_CHARACTERS:
            raise serializers.ValidationError("Name has characters that aren't allowed.", code="name_characters")
    if not any(unicodedata.category(c)[0] == "L" for c in name):
        raise serializers.ValidationError("Name needs at least one letter.", code="name_characters")
    squashed = name.replace(" ", "").casefold()
    if any(part in squashed for part in choices.RESERVED_NAME_PARTS):
        raise serializers.ValidationError("That name isn't allowed.", code="name_not_allowed")
    return name


class ProfileUpdateInput(serializers.Serializer):
    """PATCH /api/me/profile/: send only what changes."""

    display_name = serializers.CharField(max_length=60, trim_whitespace=False)
    avatar = serializers.ChoiceField(choices=choices.AVATARS)
    # "" hides the country.
    country = serializers.CharField(max_length=2, allow_blank=True)
    languages = serializers.ListField(
        child=serializers.ChoiceField(choices=choices.LANGUAGES),
        max_length=choices.MAX_LANGUAGES,
        allow_empty=True,
    )

    def validate_display_name(self, value):
        return clean_display_name(value)

    def validate_country(self, value):
        code = value.upper()
        if code and code not in COUNTRY_CODES:
            raise serializers.ValidationError("Unknown country.", code="invalid_choice")
        return code

    def validate_languages(self, value):
        # Keep the player's order, drop repeats.
        return list(dict.fromkeys(value))
