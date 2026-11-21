"""
Work out an account's entitlements: collect its sources, apply the grants in
order (inheritance and revokes inside a source type), merge per privilege, then
apply the team's overrides (a deny wins). The answer is cached for a minute and
forgotten whenever its inputs change (``forget``).

    snapshot(user) -> {"game_exp_bonus": 10, "royal_items": True}
    has(user, code) -> bool
    value(user, code, default=0) -> int
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from django.core.cache import cache
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .models import Privilege, PrivilegeGrant, SourceType, UserPrivilegeOverride, active_q

CACHE_SECONDS = 60
_VERSION_KEY = "entitlements:version"


@dataclass(frozen=True)
class SourceMatch:
    """Grants of ``source_type`` that apply: all, or only ``keys``, up to ``max_rank``."""

    source_type: str
    keys: frozenset[str] | None = None
    max_rank: int | None = None


# Who decides which sources an account has. Royal, VIP and events add theirs later.
_RESOLVERS: dict[str, Callable[[Any, Any], list[SourceMatch]]] = {}


def register_source(source_type: str, resolver: Callable[[Any, Any], list[SourceMatch]]) -> None:
    _RESOLVERS[source_type] = resolver


def _base(user, now) -> list[SourceMatch]:
    return [SourceMatch(SourceType.BASE)]


def _items(user, now) -> list[SourceMatch]:
    from items.services import owned_items

    keys = frozenset(f"item:{entry['item'].code}" for entry in owned_items(user, now))
    return [SourceMatch(SourceType.ITEM, keys=keys)]


register_source(SourceType.BASE, _base)
register_source(SourceType.ITEM, _items)


def compute(user, now=None) -> dict[str, Any]:
    """The entitlements, worked out now (no cache)."""
    now = now or timezone.now()
    matches = [m for resolver in _RESOLVERS.values() for m in resolver(user, now)]
    if not matches:
        return {}
    where = Q(pk__in=[])
    for m in matches:
        q = Q(source_type=m.source_type)
        if m.keys is not None:
            q &= Q(source_key__in=m.keys)
        if m.max_rank is not None:
            q &= Q(rank__lte=m.max_rank)
        where |= q
    grants = (
        PrivilegeGrant.objects.filter(where, active_q(now), privilege__active=True)
        .filter(Q(starts_at__isnull=True) | Q(starts_at__lte=now))
        .select_related("privilege")
        .order_by("source_type", "rank", "id")
    )
    # Per privilege, per source type: the values still standing after revokes.
    standing: dict[str, dict[str, list[int]]] = {}
    privileges: dict[str, Privilege] = {}
    for grant in grants:
        code = grant.privilege.code
        privileges[code] = grant.privilege
        values = standing.setdefault(code, {}).setdefault(grant.source_type, [])
        if grant.mode == PrivilegeGrant.Mode.REVOKE:
            values.clear()  # a higher rank takes back what the lower ones gave
        else:
            values.append(grant.value)
    result: dict[str, Any] = {}
    for code, by_type in standing.items():
        values = [v for vs in by_type.values() for v in vs]
        if values:
            result[code] = _merge(privileges[code], values)
    overrides = (
        UserPrivilegeOverride.objects.filter(active_q(now), user=user, privilege__active=True)
        .select_related("privilege")
        .order_by("created_at")
    )
    denied = set()
    for override in overrides:
        code = override.privilege.code
        if override.mode == UserPrivilegeOverride.Mode.DENY:
            denied.add(code)
        else:
            current = result.get(code)
            values = [override.value] + ([] if current is None or current is True else [current])
            result[code] = _merge(override.privilege, values)
    for code in denied:  # a deny wins over everything
        result.pop(code, None)
    return result


def _merge(privilege: Privilege, values: list[int]) -> Any:
    if privilege.value_type == Privilege.ValueType.FLAG:
        return True
    if privilege.merge == Privilege.Merge.SUM:
        return int(sum(values))
    return int(max(values))


def _version() -> int:
    return cache.get_or_set(_VERSION_KEY, 1, None)


def _key(user) -> str:
    return f"entitlements:{user.pk}:{_version()}"


def snapshot(user, now=None) -> dict[str, Any]:
    """The account's entitlements (cached for a minute; pass ``now`` to skip the cache)."""
    if now is not None:
        return compute(user, now)
    key = _key(user)
    found = cache.get(key)
    if found is None:
        found = compute(user)
        cache.set(key, found, CACHE_SECONDS)
    return found


def has(user, code: str, now=None) -> bool:
    return bool(snapshot(user, now).get(code))


def value(user, code: str, default: int = 0, now=None) -> int:
    found = snapshot(user, now).get(code)
    if found is None:
        return default
    return 1 if found is True else int(found)


def forget(user) -> None:
    """
    Its inputs changed (an item, an override ...): after the commit, work the
    entitlements out again and tell the account if they changed.
    """

    key = _key(user)
    before = cache.get(key)
    cache.delete(key)  # nothing reads the old answer from now on

    def refresh():
        key = _key(user)
        now = compute(user)
        cache.set(key, now, CACHE_SECONDS)
        if before != now:
            from realtime.publish import publish

            publish(f"user/{user.player_id}", "entitlements_updated", payload(user, now))

    transaction.on_commit(refresh)


def forget_everyone() -> None:
    """The rules changed (catalog or grants): every cached answer is old now."""
    try:
        cache.incr(_VERSION_KEY)
    except ValueError:
        cache.set(_VERSION_KEY, 2, None)


def payload(user, values: dict[str, Any] | None = None) -> dict[str, Any]:
    """What the app gets: the values, and how to show each privilege the account has."""
    values = snapshot(user) if values is None else values
    catalog = {p.code: p for p in Privilege.objects.filter(code__in=list(values))}
    return {
        "entitlements": values,
        "privileges": [
            {
                "code": p.code,
                "name": p.name,
                "description": p.description,
                "icon": p.icon,
                "value_type": p.value_type,
                "value": values[p.code],
                "built": p.built,
            }
            for p in sorted(catalog.values(), key=lambda p: (p.sort_order, p.code))
        ],
    }
