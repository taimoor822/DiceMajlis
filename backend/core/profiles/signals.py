from django.conf import settings
from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import Profile, default_avatar, default_display_name


@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def create_profile(sender, instance, created, raw=False, **kwargs):
    """Every new account gets its profile in the same transaction."""
    if created and not raw:
        Profile.objects.create(
            user=instance,
            display_name=default_display_name(instance),
            avatar=default_avatar(instance),
        )
