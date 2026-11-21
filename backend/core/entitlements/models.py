"""
Privileges and where they come from (ROYAL_VIP_ECONOMY §9).

- ``Privilege``: the catalog (admin data). ``built`` says whether the app does
  anything with it yet; the rest are listed as "coming soon".
- ``PrivilegeGrant``: a source gives (or takes back) a privilege. Sources today:
  ``base`` (everyone) and ``item`` (owning an item, key ``item:<code>``). Royal
  levels, VIP tiers and events join later through the same table: grants of one
  source type apply in ``rank`` order, so a higher level inherits the lower ones
  unless it revokes them.
- ``UserPrivilegeOverride``: the team allows or denies one privilege for one
  account (with a reason, maybe until a date). A deny wins over everything.
"""

from django.conf import settings
from django.db import models
from django.db.models import Q


class Privilege(models.Model):
    class ValueType(models.TextChoices):
        FLAG = "flag", "Flag (on/off)"
        NUMBER = "number", "Number"
        LIMIT = "limit", "Limit"

    class Merge(models.TextChoices):
        ANY = "any", "Any source (flags)"
        MAX = "max", "Highest value"
        SUM = "sum", "Added up"

    code = models.SlugField(max_length=64, unique=True)
    name = models.CharField(max_length=60)
    description = models.CharField(max_length=200)
    # A picture the app draws (a key it knows; unknown keys get a plain star).
    icon = models.CharField(max_length=32, default="star")
    value_type = models.CharField(max_length=8, choices=ValueType.choices, default=ValueType.FLAG)
    merge = models.CharField(max_length=4, choices=Merge.choices, default=Merge.ANY)
    category = models.CharField(max_length=30, blank=True, default="")
    # Does the app act on it yet? Others are listed as "coming soon".
    built = models.BooleanField(default=False)
    active = models.BooleanField(default=True)
    sort_order = models.IntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "code"]

    def __str__(self) -> str:
        return f"{self.name} ({self.code})"


class SourceType(models.TextChoices):
    BASE = "base", "Everyone"
    ITEM = "item", "Owning an item"
    ROYAL_LEVEL = "royal_level", "Royal level (later)"
    VIP_TIER = "vip_tier", "VIP tier (later)"
    EVENT = "event", "Event (later)"


class PrivilegeGrant(models.Model):
    class Mode(models.TextChoices):
        GRANT = "grant", "Grant"
        REVOKE = "revoke", "Revoke"

    source_type = models.CharField(max_length=16, choices=SourceType.choices)
    # Which source: "base", "item:<code>", later "royal:3", "vip:baron" ...
    source_key = models.CharField(max_length=80)
    # Order inside a source type (a Royal level, a VIP tier's rank); higher ranks
    # inherit lower ones and may revoke them.
    rank = models.IntegerField(default=0)
    privilege = models.ForeignKey(Privilege, related_name="grants", on_delete=models.CASCADE)
    # For numbers and limits; flags ignore it.
    value = models.BigIntegerField(default=1)
    mode = models.CharField(max_length=6, choices=Mode.choices, default=Mode.GRANT)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["source_type", "rank", "id"]
        indexes = [models.Index(fields=["source_type", "source_key"], name="grant_source_idx")]

    def __str__(self) -> str:
        return f"{self.source_key} {self.mode}s {self.privilege.code}"


class UserPrivilegeOverride(models.Model):
    class Mode(models.TextChoices):
        ALLOW = "allow", "Allow"
        DENY = "deny", "Deny"

    user = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="privilege_overrides", on_delete=models.CASCADE)
    privilege = models.ForeignKey(Privilege, related_name="overrides", on_delete=models.CASCADE)
    mode = models.CharField(max_length=5, choices=Mode.choices)
    value = models.BigIntegerField(default=1)
    reason = models.CharField(max_length=200)
    ends_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="+", null=True, on_delete=models.SET_NULL)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "ends_at"], name="override_user_idx")]

    def __str__(self) -> str:
        return f"{self.mode} {self.privilege.code} for {self.user}"


def active_q(now) -> Q:
    """Grants and overrides that apply at ``now``."""
    return (Q(ends_at__isnull=True) | Q(ends_at__gt=now))
