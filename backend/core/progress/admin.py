from django import forms
from django.contrib import admin

from rewards.engine import check_bundle

from .metrics import METRICS
from .models import Achievement, AchievementTier, AchievementUnlock


class AchievementForm(forms.ModelForm):
    metric = forms.ChoiceField(choices=[(code, label) for code, (label, _) in METRICS.items()])

    class Meta:
        model = Achievement
        fields = "__all__"


class TierForm(forms.ModelForm):
    class Meta:
        model = AchievementTier
        fields = ("threshold", "reward")

    def clean_reward(self):
        reward = self.cleaned_data["reward"] or {}
        if reward:
            try:
                check_bundle(reward)
            except ValueError as e:
                raise forms.ValidationError(str(e))
        return reward


class TierInline(admin.TabularInline):
    model = AchievementTier
    form = TierForm
    extra = 1


@admin.register(Achievement)
class AchievementAdmin(admin.ModelAdmin):
    """The catalog. After adding one, run `manage.py check_achievements` to unlock it for
    players who already qualify. Untick "active" instead of deleting."""

    form = AchievementForm
    list_display = ("code", "name", "metric", "rarity", "hidden", "active", "sort_order")
    list_filter = ("metric", "rarity", "hidden", "active")
    search_fields = ("code", "name")
    inlines = [TierInline]

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(AchievementUnlock)
class AchievementUnlockAdmin(admin.ModelAdmin):
    list_display = ("user", "tier", "value", "reward_claim", "unlocked_at")
    search_fields = ("=user__player_id", "tier__achievement__code")
    date_hierarchy = "unlocked_at"

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
