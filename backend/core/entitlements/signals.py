"""Forget cached entitlements when the rules or an account's overrides change."""

from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from . import engine
from .models import Privilege, PrivilegeGrant, UserPrivilegeOverride


@receiver([post_save, post_delete], sender=Privilege)
@receiver([post_save, post_delete], sender=PrivilegeGrant)
def rules_changed(sender, **kwargs):
    engine.forget_everyone()


@receiver([post_save, post_delete], sender=UserPrivilegeOverride)
def override_changed(sender, instance, **kwargs):
    engine.forget(instance.user)
