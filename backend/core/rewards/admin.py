from django import forms
from django.contrib import admin

from .engine import check_bundle
from .models import DailyRewardDay, DailyRewardSettings, RewardBundle, RewardClaim


@admin.register(RewardClaim)
class RewardClaimAdmin(admin.ModelAdmin):
    """Every reward given (read only: rewards are given by the server, not by hand)."""

    list_display = ("user", "kind", "source", "reward_day", "streak_day", "bundle", "created_at")
    list_filter = ("kind",)
    search_fields = ("=user__player_id", "idempotency_key", "source")
    date_hierarchy = "created_at"

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


class RewardBundleForm(forms.ModelForm):
    class Meta:
        model = RewardBundle
        fields = ("code", "name", "contents", "active")
        help_texts = {
            "contents": 'e.g. {"gold": 500, "diamond": 5, "xp": 50, '
            '"items": [{"code": "dice_pearl", "quantity": 1, "days": 7}]}',
        }

    def clean_contents(self):
        try:
            return check_bundle(self.cleaned_data["contents"])
        except ValueError as e:
            raise forms.ValidationError(str(e))


@admin.register(RewardBundle)
class RewardBundleAdmin(admin.ModelAdmin):
    """Reward bundles the team sets up (daily reward days today; events and VIP later)."""

    form = RewardBundleForm
    list_display = ("code", "name", "contents", "active")
    search_fields = ("code", "name")

    def has_delete_permission(self, request, obj=None):
        return False  # untick "active"; claims keep what they gave


@admin.register(DailyRewardDay)
class DailyRewardDayAdmin(admin.ModelAdmin):
    """The daily login cycle: day 1, 2, 3 ... and the bundle each gives."""

    list_display = ("day", "bundle")
    autocomplete_fields = ("bundle",)


@admin.register(DailyRewardSettings)
class DailyRewardSettingsAdmin(admin.ModelAdmin):
    list_display = ("__str__",)

    def has_add_permission(self, request):
        return not DailyRewardSettings.objects.exists()

    def has_delete_permission(self, request, obj=None):
        return False
