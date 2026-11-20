from django.db import migrations

# Same defaults as profiles.models (copied: migrations must not import app code).
AVATARS = (
    "dice", "trophy", "star", "moon", "sun", "coffee", "dhow", "tree",
    "diamond", "rocket", "music", "football", "paw", "flower", "bolt", "gamepad",
)


def create_missing_profiles(apps, schema_editor):
    """Accounts made before profiles existed get one now."""
    User = apps.get_model("accounts", "User")
    Profile = apps.get_model("profiles", "Profile")
    for user in User.objects.filter(profile__isnull=True).iterator():
        Profile.objects.create(
            user=user,
            display_name=f"Player {user.player_id % 10000:04d}",
            avatar=AVATARS[user.player_id % len(AVATARS)],
        )


class Migration(migrations.Migration):
    dependencies = [
        ("profiles", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(create_missing_profiles, migrations.RunPython.noop),
    ]
