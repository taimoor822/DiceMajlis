"""
``/ws/v1/``: the app's one live connection (ARCHITECTURE.md §7).

1. The app connects and, within ``REALTIME_AUTH_TIMEOUT_SECONDS`` (5 s), sends
   ``{"v":1,"type":"auth","req_id":…,"data":{"access_token":…}}``. The token goes
   in a message, not the URL, so it never lands in proxy logs. A bad or expired
   token closes the socket with 4401 (the app refreshes and reconnects); no auth
   in time closes it with 4408.
2. Then it sends ``ping`` every ``REALTIME_HEARTBEAT_SECONDS`` (presence), and
   ``subscribe`` / ``unsubscribe`` to channels (``realtime.topics``). Every
   subscription is checked; a new subscriber first gets the channel's current state.
3. Other requests go to the handlers features register (``realtime.handlers``),
   with rate limits and remembered replies (``realtime.limits``).

The signed-in device session is checked again at most every
``REALTIME_SESSION_CHECK_SECONDS``: a device that was signed out loses its socket.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time

from asgiref.sync import sync_to_async
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.conf import settings

from accounts import tokens
from accounts.models import DeviceSession

from . import handlers, limits, presence, protocol, topics
from .handlers import Context
from .protocol import ProtocolError

logger = logging.getLogger(__name__)


def _signed_in(access_token: str):
    """The account and device session behind an access token, or TokenError."""
    claims = tokens.decode_access(access_token)
    session = (
        DeviceSession.objects.select_related("user")
        .filter(id=claims["sid"], user_id=claims["sub"])
        .first()
    )
    if session is None or not session.is_active or not session.user.is_active:
        raise tokens.TokenError("Signed out", code="session_revoked")
    return session.user, session


def _session_still_active(session_id) -> bool:
    session = DeviceSession.objects.select_related("user").filter(id=session_id).first()
    return session is not None and session.is_active and session.user.is_active


class RealtimeConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.user = None
        self.session_id = None
        self.subscriptions: dict[str, str] = {}  # channel name -> group
        self._checked_session_at = 0.0
        self._closing = False
        await self.accept()
        self._auth_timer = asyncio.ensure_future(self._auth_deadline())

    async def disconnect(self, code):
        timer = getattr(self, "_auth_timer", None)
        if timer is not None:
            timer.cancel()
        for group in getattr(self, "subscriptions", {}).values():
            await self.channel_layer.group_discard(group, self.channel_name)
        if getattr(self, "user", None) is not None:
            await sync_to_async(presence.disconnected)(self.user.id)

    # ---- incoming ------------------------------------------------------------

    async def receive(self, text_data=None, bytes_data=None):
        if self._closing:
            return
        if text_data is None:
            await self._refuse(protocol.error(None, "invalid_message", "Send text (JSON) messages"))
            return
        if len(text_data.encode("utf-8")) > settings.REALTIME_MAX_MESSAGE_BYTES:
            await self._close(protocol.CLOSE_TOO_BIG)
            return
        try:
            request = protocol.parse(text_data)
        except ProtocolError as exc:
            await self._refuse(protocol.error(protocol.req_id_of(text_data), exc.code, exc.message))
            return

        if self.user is None:
            await self._authenticate(request)
        else:
            await self._dispatch(request)

    async def _refuse(self, reply: dict) -> None:
        """Answer a bad message. Before sign-in, a bad message also ends the socket."""
        await self._send(reply)
        if self.user is None:
            await self._close(protocol.CLOSE_BAD_TOKEN)

    async def _authenticate(self, request: protocol.Request) -> None:
        if request.type != protocol.AUTH:
            await self._refuse(protocol.error(request.req_id, "auth_required", "Send auth first"))
            return
        token = request.data.get("access_token")
        if not isinstance(token, str) or not token or len(token) > 2048:
            await self._refuse(protocol.error(request.req_id, "invalid_token", "Missing access token"))
            return
        try:
            user, session = await database_sync_to_async(_signed_in)(token)
        except tokens.TokenError as exc:
            await self._refuse(protocol.error(request.req_id, exc.code, str(exc)))
            return

        self._auth_timer.cancel()
        self.user = user
        self.session_id = str(session.id)
        self._checked_session_at = time.monotonic()
        await sync_to_async(presence.connected)(user.id)
        await self._send(protocol.ack(request.req_id, {
            "player_id": user.player_id,
            "heartbeat_seconds": settings.REALTIME_HEARTBEAT_SECONDS,
        }))

    async def _dispatch(self, request: protocol.Request) -> None:
        kind = request.type
        if kind == protocol.AUTH:
            await self._send(protocol.error(request.req_id, "already_authenticated", "Already signed in"))
            return
        if kind == protocol.PING:
            if await self._allowed(request, "control"):
                await self._ping(request)
            return
        if kind == protocol.SUBSCRIBE:
            if await self._allowed(request, "subscribe"):
                await self._subscribe(request)
            return
        if kind == protocol.UNSUBSCRIBE:
            if await self._allowed(request, "control"):
                await self._unsubscribe(request)
            return
        entry = handlers.get(kind)
        if entry is None:
            await self._send(protocol.error(request.req_id, "unknown_type", f"Unknown request {kind}"))
            return
        if await self._allowed(request, entry.bucket):
            await self._handle(entry, request)

    async def _allowed(self, request: protocol.Request, bucket: str) -> bool:
        verdict = await sync_to_async(limits.hit)(self.user.id, bucket)
        if verdict is limits.Verdict.OK:
            return True
        await self._send(protocol.error(request.req_id, "rate_limited", "Too many messages, slow down"))
        if verdict is limits.Verdict.ABUSE:
            await self._close(protocol.CLOSE_RATE_LIMITED)
        return False

    # ---- built-in requests -------------------------------------------------------

    async def _ping(self, request: protocol.Request) -> None:
        now = time.monotonic()
        if now - self._checked_session_at >= settings.REALTIME_SESSION_CHECK_SECONDS:
            self._checked_session_at = now
            if not await database_sync_to_async(_session_still_active)(self.session_id):
                await self._send(protocol.error(request.req_id, "session_revoked", "Signed out"))
                await self._close(protocol.CLOSE_BAD_TOKEN)
                return
        await sync_to_async(presence.heartbeat)(self.user.id)
        await self._send(protocol.pong(request.req_id))

    async def _subscribe(self, request: protocol.Request) -> None:
        try:
            topic, channel = topics.resolve(request.data.get("channel"))
            if (
                channel.name not in self.subscriptions
                and len(self.subscriptions) >= settings.REALTIME_MAX_SUBSCRIPTIONS
            ):
                raise ProtocolError("too_many_subscriptions", "Unsubscribe from something first")
            await database_sync_to_async(topic.authorize)(self.user, channel.key)
        except ProtocolError as exc:
            await self._send(protocol.error(request.req_id, exc.code, exc.message))
            return

        # Join first, then read the current state: nothing that changes in
        # between is missed (events carry versions, so older ones are ignored).
        await self.channel_layer.group_add(channel.group, self.channel_name)
        self.subscriptions[channel.name] = channel.group
        initial = await database_sync_to_async(topic.initial_events)(self.user, channel.key)
        await self._send(protocol.ack(request.req_id, {"channel": channel.name}))
        for message in initial:
            await self._send(message)

    async def _unsubscribe(self, request: protocol.Request) -> None:
        name = request.data.get("channel")
        group = self.subscriptions.pop(name, None) if isinstance(name, str) else None
        if group is not None:
            await self.channel_layer.group_discard(group, self.channel_name)
        await self._send(protocol.ack(request.req_id, {"channel": name}))

    # ---- feature requests -----------------------------------------------------------

    async def _handle(self, entry: handlers.Handler, request: protocol.Request) -> None:
        req_id = request.req_id
        user_id = self.user.id
        if entry.changes_state:
            if req_id is None:
                await self._send(protocol.error(None, "req_id_required", "This request needs a req_id"))
                return
            earlier = await sync_to_async(limits.claim)(user_id, req_id)
            if earlier == limits.PENDING:
                await self._send(protocol.error(req_id, "request_in_progress", "Still working on it"))
                return
            if earlier is not None:
                await self._send(earlier)  # a retry: the first answer, not a second action
                return

        context = Context(user=self.user, session_id=self.session_id)
        try:
            data = await database_sync_to_async(entry.fn)(context, request.data)
            reply = protocol.ack(req_id, data or {})
        except ProtocolError as exc:
            reply = protocol.error(req_id, exc.code, exc.message)
        except Exception:
            logger.exception("socket request %s failed", entry.type)
            if entry.changes_state:
                await sync_to_async(limits.forget)(user_id, req_id)
            await self._send(protocol.error(req_id, "server_error", "Something went wrong"))
            return
        if entry.changes_state:
            await sync_to_async(limits.remember)(user_id, req_id, reply)
        await self._send(reply)

    # ---- outgoing ---------------------------------------------------------------

    async def realtime_event(self, message):
        """An event published on a channel this socket subscribed to."""
        if self.user is not None and not self._closing:
            await self._send(message["event"])

    async def _send(self, message: dict) -> None:
        await self.send(text_data=json.dumps(message, separators=(",", ":")))

    async def _close(self, code: int) -> None:
        if not self._closing:
            self._closing = True
            await self.close(code=code)

    async def _auth_deadline(self) -> None:
        await asyncio.sleep(settings.REALTIME_AUTH_TIMEOUT_SECONDS)
        if self.user is None and not self._closing:
            await self._send(protocol.error(None, "auth_timeout", "Sign in took too long"))
            await self._close(protocol.CLOSE_AUTH_TIMEOUT)
