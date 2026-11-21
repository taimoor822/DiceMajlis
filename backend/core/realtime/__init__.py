"""
The one live connection of the app: ``/ws/v1/`` (ARCHITECTURE.md §7).

    protocol.py   message shapes, close codes, error codes (no Django)
    topics.py     the channels a socket can subscribe to and who may
    publish.py    how the server pushes an event to a channel
    presence.py   who is online (heartbeats)
    limits.py     per-account rate limits and remembered replies (idempotency)
    consumers.py  the socket itself

Features push to a channel with ``publish(channel, type, data)``; they never talk
to sockets directly.
"""
