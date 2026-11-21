"""The first achievements. Rewards are placeholders (gold and diamonds through
rewards.grant()); edit them in the admin, then run `manage.py check_achievements`."""

from django.db import migrations

ACHIEVEMENTS = [
    # code, name, description, icon, rarity, metric, hidden, sort, [(threshold, reward)]
    ("games_played", "Regular Guest", "Play online games against other people to the end.", "dice",
     "common", "games_played", False, 10,
     [(1, {"gold": 50}), (10, {"gold": 100}), (100, {"gold": 500}), (1000, {"diamond": 5})]),
    ("wins", "Victories", "Win online games against other people.", "trophy",
     "common", "wins", False, 20,
     [(1, {"gold": 100}), (10, {"gold": 300}), (50, {"gold": 1000})]),
    ("win_streak", "On a Roll", "Win online games in a row.", "flame",
     "rare", "best_win_streak", False, 30,
     [(3, {"gold": 200}), (5, {"gold": 500}), (10, {"diamond": 10})]),
    ("level", "Rising Star", "Reach a higher account level.", "star",
     "common", "level", False, 40,
     [(5, {"gold": 200}), (10, {"gold": 500}), (20, {"diamond": 5})]),
    ("majlis_legend", "Majlis Legend", "Win 100 online games.", "crown",
     "legendary", "wins", True, 50,
     [(100, {"diamond": 20})]),
]


def add(apps, schema_editor):
    Achievement = apps.get_model("progress", "Achievement")
    Tier = apps.get_model("progress", "AchievementTier")
    for code, name, description, icon, rarity, metric, hidden, sort, tiers in ACHIEVEMENTS:
        achievement, _ = Achievement.objects.update_or_create(
            code=code,
            defaults={
                "name": name, "description": description, "icon": icon, "rarity": rarity,
                "metric": metric, "hidden": hidden, "sort_order": sort,
            },
        )
        for threshold, reward in tiers:
            Tier.objects.update_or_create(achievement=achievement, threshold=threshold, defaults={"reward": reward})


class Migration(migrations.Migration):
    dependencies = [("progress", "0001_achievements")]

    operations = [migrations.RunPython(add, migrations.RunPython.noop)]
