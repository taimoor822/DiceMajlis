"""The starting privilege catalog (ROYAL_VIP_ECONOMY §10) as data. Which sources
give which values is admin data too (none yet: Royal and VIP come in Phase 10).
"built" = the app acts on it today; the others are listed as coming soon."""

from django.db import migrations

# code, name, description, icon, value_type, merge, category, built
CATALOG = [
    ("game_exp_bonus", "Game XP bonus", "Extra account XP from online games, in percent (never rating).", "bolt", "number", "max", "progress", True),
    ("higher_exp_limit", "Higher XP limit", "Raises the daily limit of XP from games.", "trending_up", "number", "max", "progress", True),
    ("royal_items", "Royal items", "May wear Royal-only items.", "diamond", "flag", "any", "items", True),
    ("royal_profile_frame", "Royal frame", "Unlocks the Royal profile frame.", "frame", "flag", "any", "items", True),
    ("super_fragment_exchange", "Super Fragment Exchange", "Premium offers in the Fragment Exchange.", "swap", "flag", "any", "rewards", False),
    ("visitor_history", "Visitor history", "How many profile visitors are kept and shown.", "visibility", "limit", "max", "profile", False),
    ("stealth_visit", "Stealth visit", "Your visits aren't recorded in other people's history.", "visibility_off", "flag", "any", "profile", False),
    ("royal_logo", "Royal emblem", "A Royal emblem next to your name.", "crown", "flag", "any", "profile", False),
    ("photo_enlarge", "Photo enlarge", "Others can open your avatar full-size.", "zoom", "flag", "any", "profile", False),
    ("display_on_top", "Shown higher", "Higher in room and friend lists (social lists only).", "arrow_up", "number", "max", "social", False),
    ("priority_ranking", "Social priority", "Higher in social lists only, never in competitive ones.", "arrow_up", "number", "max", "social", False),
    ("skin_sync", "Skin sync", "Your profile skin also styles rooms you own.", "palette", "flag", "any", "rooms", False),
    ("theme_sync", "Theme sync", "Your theme also styles rooms you own.", "palette", "flag", "any", "rooms", False),
    ("pin_friends", "Pinned friends", "How many friends you can pin on top.", "pin", "limit", "max", "social", False),
    ("royal_sticker", "Royal stickers", "The Royal sticker pack in chat.", "sticker", "flag", "any", "chat", False),
    ("full_room_access", "Full room access", "Enter rooms that are at their online limit.", "door", "flag", "any", "rooms", False),
    ("exclusive_launch_screen", "Royal welcome", "A Royal welcome screen after the app starts.", "star", "flag", "any", "app", False),
    ("profile_page_skin", "Profile background", "A custom profile background.", "image", "flag", "any", "profile", False),
    ("announcement_image", "Announcement images", "Images in room announcements.", "image", "flag", "any", "rooms", False),
    ("royal_reward_tower", "Reward Tower", "Access to the Royal Reward Tower.", "tower", "flag", "any", "rewards", False),
    ("longer_bio", "Longer bio", "How long your bio may be.", "notes", "limit", "max", "profile", False),
    ("customer_service_priority", "Support priority", "Your support messages are answered first.", "support", "number", "max", "support", False),
    ("royal_app_icon", "Royal app icon", "Choose a Royal app icon.", "apps", "flag", "any", "app", False),
    ("voice_messaging", "Voice messages", "Send voice messages in private chat.", "mic", "flag", "any", "chat", False),
    ("recharge_ticket", "Recharge tickets", "Recharge tickets each month.", "ticket", "number", "sum", "store", False),
    ("super_value_surprise", "Value surprise", "Free surprise draws each day.", "gift", "number", "max", "rewards", False),
    ("daily_gift_commission", "Gift commission", "Access to gift-commission tasks.", "gift", "flag", "any", "rewards", False),
    ("gif_privileges", "GIFs in chat", "Send GIFs in chat.", "gif", "flag", "any", "chat", False),
    ("vip_badge", "VIP badge", "A VIP badge by your name.", "badge", "flag", "any", "profile", False),
    ("vip_room_create", "Create VIP rooms", "Open VIP-only rooms.", "door", "flag", "any", "rooms", False),
    ("vip_room_access", "VIP rooms", "Enter VIP-only rooms.", "door", "flag", "any", "rooms", False),
    ("entrance_effect", "Entrance effect", "An entrance animation when you join a room.", "sparkle", "flag", "any", "rooms", False),
    ("premium_message_style", "Message style", "Styled chat bubbles and name colour.", "chat", "flag", "any", "chat", False),
]


def add(apps, schema_editor):
    Privilege = apps.get_model("entitlements", "Privilege")
    for order, (code, name, description, icon, value_type, merge, category, built) in enumerate(CATALOG):
        Privilege.objects.update_or_create(
            code=code,
            defaults={
                "name": name, "description": description, "icon": icon, "value_type": value_type,
                "merge": merge, "category": category, "built": built, "sort_order": order * 10,
            },
        )


class Migration(migrations.Migration):
    dependencies = [("entitlements", "0001_privileges")]

    operations = [migrations.RunPython(add, migrations.RunPython.noop)]
