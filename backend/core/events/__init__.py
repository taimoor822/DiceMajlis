"""
Domain events (SOCIAL_MAJLIS §11): important changes write a ``DomainEvent`` row
in the same transaction as the change (the outbox); handlers in other apps react
to it afterwards (XP, statistics, achievements, moments ...).

    from events.outbox import emit, on

    emit("game_finished", {...})          # inside the change's transaction
    on("game_finished", give_xp)          # in an app's ready()

After the commit the event is handed to its handlers right away; anything left
(a crash, a failing handler) is retried by the background sweep. Handlers must
be idempotent: an event may reach a handler more than once.
"""
