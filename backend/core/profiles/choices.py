"""
What a profile can hold. The server decides what is allowed; the app shows the
pictures and names for these keys (and a plain fallback for keys it doesn't know).
"""

# Built-in avatar pictures (the app draws each key). Photo upload comes later,
# once image storage and moderation exist.
AVATARS = (
    "dice",
    "trophy",
    "star",
    "moon",
    "sun",
    "coffee",
    "dhow",
    "tree",
    "diamond",
    "rocket",
    "music",
    "football",
    "paw",
    "flower",
    "bolt",
    "gamepad",
)

# Spoken languages a player can show on their profile (not the app's own language).
LANGUAGES = ("en", "ar", "ur", "pa")
MAX_LANGUAGES = len(LANGUAGES)

NAME_MIN_LENGTH = 2
NAME_MAX_LENGTH = 20

# Names that could pass for the team. Checked case-insensitively, ignoring spaces.
RESERVED_NAME_PARTS = ("admin", "moderator", "dicemajlis", "official", "support", "staff")
