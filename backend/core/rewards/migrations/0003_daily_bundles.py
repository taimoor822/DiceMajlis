"""The daily login cycle as admin data: one bundle per day (the amounts from 1.8,
and day 7 now also lends the Pearl dice for 7 days and gives 20 XP)."""

from django.db import migrations

DAYS = [
    {"gold": 100},
    {"gold": 150},
    {"gold": 200},
    {"gold": 250},
    {"gold": 300},
    {"gold": 400},
    {"gold": 500, "diamond": 5, "xp": 20, "items": [{"code": "dice_pearl", "quantity": 1, "days": 7}]},
]


def add(apps, schema_editor):
    RewardBundle = apps.get_model("rewards", "RewardBundle")
    DailyRewardDay = apps.get_model("rewards", "DailyRewardDay")
    DailyRewardSettings = apps.get_model("rewards", "DailyRewardSettings")
    for number, contents in enumerate(DAYS, start=1):
        bundle, _ = RewardBundle.objects.update_or_create(
            code=f"daily_day{number}", defaults={"name": f"Daily reward, day {number}", "contents": contents}
        )
        DailyRewardDay.objects.update_or_create(day=number, defaults={"bundle": bundle})
    DailyRewardSettings.objects.get_or_create(pk=1)


class Migration(migrations.Migration):
    dependencies = [
        ("rewards", "0002_reward_bundles"),
        ("items", "0002_starter_catalog"),
    ]

    operations = [migrations.RunPython(add, migrations.RunPython.noop)]
