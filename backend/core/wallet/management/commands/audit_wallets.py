from django.core.management.base import BaseCommand, CommandError

from wallet.services import audit


class Command(BaseCommand):
    help = "Check that every wallet balance matches its ledger (run nightly)."

    def handle(self, *args, **options):
        problems = audit()
        for problem in problems:
            self.stderr.write(problem)
        if problems:
            raise CommandError(f"{len(problems)} wallet problem(s) found")
        self.stdout.write("All wallet balances match their ledgers.")
