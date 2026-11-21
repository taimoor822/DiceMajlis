from django.core.management.base import BaseCommand

from game.rooms import start_due_rooms
from game.timers import process_due_turns, run_forever


class Command(BaseCommand):
    help = "Auto-play turns whose timer ran out (use with GAME_TIMER_IN_PROCESS=false)."

    def add_arguments(self, parser):
        parser.add_argument("--interval", type=float, default=1.0, help="Seconds between sweeps.")
        parser.add_argument("--once", action="store_true", help="Run a single sweep and exit.")

    def handle(self, *args, **options):
        if options["once"]:
            handled = process_due_turns()
            started = start_due_rooms()
            self.stdout.write(f"Handled {handled} overdue turn(s), started {started} room(s).")
            return
        self.stdout.write(f"Turn timer running every {options['interval']}s. Ctrl+C to stop.")
        try:
            run_forever(options["interval"])
        except KeyboardInterrupt:
            self.stdout.write("Stopped.")
