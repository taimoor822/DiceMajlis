"""Reading and changing profiles. Views and other apps go through here."""

from .levels import level_progress
from .models import Profile, default_avatar, default_display_name


def profile_of(user) -> Profile:
    """The account's profile (created on the spot for an account that has none)."""
    try:
        return user.profile
    except Profile.DoesNotExist:
        profile, _ = Profile.objects.get_or_create(
            user=user,
            defaults={
                "display_name": default_display_name(user),
                "avatar": default_avatar(user),
            },
        )
        return profile


def profile_payload(user) -> dict:
    """What the account owner sees about their own profile."""
    profile = profile_of(user)
    return {
        "display_name": profile.display_name,
        "avatar": profile.avatar,
        "country": profile.country or None,
        "languages": list(profile.languages),
        **level_progress(profile.xp),
    }


def update_profile(user, changes: dict) -> Profile:
    """Apply checked changes (profiles.serializers.ProfileUpdateInput)."""
    profile = profile_of(user)
    for field, value in changes.items():
        setattr(profile, field, value)
    if changes:
        profile.save(update_fields=[*changes, "updated_at"])
    return profile
