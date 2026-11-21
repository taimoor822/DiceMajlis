"""The first cosmetics. Starter items are owned by every account; the rest come
from achievements, rewards and the admin. Edit the catalog in the admin."""

from django.db import migrations

CATALOG = [
    # code, slot, name, description, rarity, starter, sort
    ("dice_ivory", "dice", "Ivory", "The classic white die.", "common", True, 0),
    ("dice_desert_gold", "dice", "Desert Gold", "Gold as the dunes at sunset.", "rare", True, 10),
    ("dice_night_sky", "dice", "Night Sky", "Deep blue with starlight pips.", "rare", False, 20),
    ("dice_pearl", "dice", "Pearl", "Gulf pearl with a teal shine.", "epic", False, 30),
    ("dice_ruby", "dice", "Ruby", "A red jewel of a die.", "epic", False, 40),
    ("board_majlis", "board", "Majlis", "The house table.", "common", True, 0),
    ("board_oasis", "board", "Oasis", "Cool palm-green around the board.", "rare", True, 10),
    ("board_sandstone", "board", "Sandstone", "Warm desert stone.", "rare", False, 20),
    ("board_midnight", "board", "Midnight", "Night blue with a gold trim.", "epic", False, 30),
    ("frame_brass", "frame", "Brass Ring", "A simple polished ring.", "common", True, 0),
    ("frame_lantern", "frame", "Lantern Glow", "Warm light from a hanging lantern.", "rare", False, 10),
    ("frame_palm", "frame", "Palm Arch", "Green and gold, like a palm grove.", "epic", False, 20),
    ("frame_falcon", "frame", "Falcon Crest", "For the sharpest players.", "legendary", False, 30),
]


def add_catalog(apps, schema_editor):
    ItemDefinition = apps.get_model("items", "ItemDefinition")
    for code, slot, name, description, rarity, starter, sort in CATALOG:
        ItemDefinition.objects.update_or_create(
            code=code,
            defaults={
                "type": "cosmetic",
                "subtype": slot,
                "name": name,
                "description": description,
                "rarity": rarity,
                "asset": code,
                "is_starter": starter,
                "sort_order": sort,
            },
        )


class Migration(migrations.Migration):
    dependencies = [("items", "0001_item_system")]

    operations = [migrations.RunPython(add_catalog, migrations.RunPython.noop)]
