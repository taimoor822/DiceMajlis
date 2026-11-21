"""Achievements now also give cosmetics (reward bundles with items, step 2.5)."""

from django.db import migrations

ITEMS = {
    ("wins", 10): ["dice_night_sky"],
    ("win_streak", 3): ["frame_lantern"],
    ("win_streak", 10): ["board_midnight"],
    ("level", 5): ["board_sandstone"],
    ("games_played", 100): ["frame_palm"],
    ("majlis_legend", 100): ["frame_falcon", "dice_ruby"],
}


def add(apps, schema_editor):
    Tier = apps.get_model("progress", "AchievementTier")
    for (code, threshold), items in ITEMS.items():
        tier = Tier.objects.filter(achievement__code=code, threshold=threshold).first()
        if tier is None:
            continue
        reward = dict(tier.reward)
        reward["items"] = [{"code": item, "quantity": 1} for item in items]
        tier.reward = reward
        tier.save(update_fields=["reward"])


class Migration(migrations.Migration):
    dependencies = [
        ("progress", "0002_first_achievements"),
        ("items", "0002_starter_catalog"),
    ]

    operations = [migrations.RunPython(add, migrations.RunPython.noop)]
