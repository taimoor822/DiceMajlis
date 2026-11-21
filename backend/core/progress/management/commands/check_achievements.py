from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

from progress.services import check


class Command(BaseCommand):
    help = "Unlock achievements players already qualify for (after adding or changing some)."

    def add_arguments(self, parser):
        parser.add_argument("--player", type=int, help="Only this Player ID.")

    def handle(self, *args, **options):
        users = get_user_model().objects.all()
        if options["player"]:
            users = users.filter(player_id=options["player"])
        unlocked = 0
        for user in users.iterator():
            unlocked += len(check(user))
        self.stdout.write(f"Unlocked {unlocked} achievement tier(s).")
