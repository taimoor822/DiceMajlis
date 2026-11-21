"""
Account XP: the one way XP changes (``add_xp``), and how much a game gives.

The numbers are placeholders, kept here on the server (the app shows what it is
sent, never works XP out itself):

    every real game you play to the end   20 XP
    1st place                            +30 XP
    2nd place, with 3 or more players    +10 XP
    left or forfeited                      0 XP
    at most 500 XP from games per reward-day (00:00 Bahrain time)

Only real games count (game.results.counts_for_progress: two or more accounts, no
bots). Offline games never reach the server.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction

from rewards.days import reward_day

from .levels import level_for_xp, level_progress
from .models import Profile, XpEntry
from .services import profile_of

GAME_XP_PLAYED = 20
GAME_XP_PLACE_BONUS = {1: 30, 2: 10}
# 2nd place only earns its bonus when it isn't also last place.
SECOND_PLACE_MIN_PLAYERS = 3
GAME_XP_DAILY_CAP = 500


@dataclass(frozen=True)
class XpAdded:
    entry: XpEntry | None  # None: nothing added (cap reached)
    created: bool  # False: already added before (same key) or nothing to add
    level_before: int
    level_after: int

    @property
    def level_up(self) -> bool:
        return self.level_after > self.level_before


def add_xp(
    user,
    amount: int,
    *,
    reason: str,
    idempotency_key: str,
    reference_type: str = "",
    reference_id: str = "",
    daily_cap: int | None = None,
    details: dict[str, Any] | None = None,
    now=None,
) -> XpAdded:
    """
    Add XP to ``user``'s profile, once per ``idempotency_key``. With ``daily_cap``
    the XP of this ``reason`` on one reward-day stops at the cap (the rest is
    dropped). Pushes ``xp_gained`` to the account after the commit, with
    ``details`` added (e.g. the game's ``room_code``).
    """
    if not isinstance(amount, int) or isinstance(amount, bool) or amount <= 0:
        raise ValueError(f"bad XP amount: {amount!r}")
    if reason not in XpEntry.Reason.values:
        raise ValueError(f"unknown XP reason {reason!r}")
    day = reward_day(now)
    profile_of(user)  # make sure it exists
    with transaction.atomic():
        profile = Profile.objects.select_for_update().get(pk=user.pk)
        level_before = level_for_xp(profile.xp)
        if profile.xp_entries.filter(idempotency_key=idempotency_key).exists():
            return XpAdded(None, False, level_before, level_before)
        if daily_cap is not None:
            earned = sum(
                profile.xp_entries.filter(reason=reason, reward_day=day).values_list("amount", flat=True)
            )
            amount = min(amount, max(0, daily_cap - earned))
            if amount <= 0:
                return XpAdded(None, False, level_before, level_before)
        try:
            with transaction.atomic():
                entry = XpEntry.objects.create(
                    profile=profile,
                    amount=amount,
                    xp_before=profile.xp,
                    xp_after=profile.xp + amount,
                    reason=reason,
                    reference_type=reference_type,
                    reference_id=reference_id,
                    reward_day=day,
                    idempotency_key=idempotency_key,
                )
        except IntegrityError:  # the same key won a race on another connection
            return XpAdded(None, False, level_before, level_before)
        Profile.objects.filter(pk=profile.pk).update(xp=entry.xp_after)
        from events.outbox import emit

        # Achievements on the level react to this (after the commit).
        emit(
            "xp_added",
            {
                "user_id": str(user.pk),
                "amount": entry.amount,
                "reason": entry.reason,
                "xp": entry.xp_after,
                "level": level_for_xp(entry.xp_after),
                "level_up": level_for_xp(entry.xp_after) > level_before,
                **(details or {}),
            },
        )
        cached = user._state.fields_cache.get("profile")  # keep user.profile current
        if cached is not None:
            cached.xp = entry.xp_after
        added = XpAdded(entry, True, level_before, level_for_xp(entry.xp_after))
        transaction.on_commit(lambda: _push_xp(user, added, details or {}))
    return added


def _push_xp(user, added: XpAdded, details: dict[str, Any]) -> None:
    from realtime.publish import publish

    entry = added.entry
    publish(
        f"user/{user.player_id}",
        "xp_gained",
        {
            "amount": entry.amount,
            "reason": entry.reason,
            "reference_type": entry.reference_type,
            "reference_id": entry.reference_id,
            "level_up": added.level_up,
            **level_progress(entry.xp_after),
            **details,
        },
    )


def game_xp(place: int, status: str, player_count: int) -> int:
    """XP for one seat of a finished real game."""
    if status == "forfeited":
        return 0
    bonus = GAME_XP_PLACE_BONUS.get(place, 0)
    if place == 2 and player_count < SECOND_PLACE_MIN_PLAYERS:
        bonus = 0
    return GAME_XP_PLAYED + bonus


def on_game_finished(payload: dict[str, Any], event=None) -> None:
    """``game_finished`` handler: XP for everyone who played a real game to the end."""
    if not payload.get("counts"):
        return
    User = get_user_model()
    game_id = str(payload["game_id"])
    for seat in payload["players"]:
        if seat["is_bot"] or not seat.get("user_id"):
            continue
        amount = game_xp(seat["place"], seat["status"], payload["player_count"])
        if amount <= 0:
            continue
        user = User.objects.filter(pk=seat["user_id"]).first()
        if user is None:  # account deleted since
            continue
        add_xp(
            user,
            amount,
            reason=XpEntry.Reason.GAME,
            idempotency_key=f"game:{game_id}",
            reference_type="game",
            reference_id=game_id,
            daily_cap=GAME_XP_DAILY_CAP,
            details={"room_code": payload["room_code"]},
            now=_parse(payload.get("finished_at")),
        )


def _parse(value):
    from django.utils.dateparse import parse_datetime

    return parse_datetime(value) if value else None
