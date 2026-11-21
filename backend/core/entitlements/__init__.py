"""
The entitlement engine (ROYAL_VIP_ECONOMY §9): the one place that answers "may
this account do X, and how much?". Never check `user.is_vip` or a level
directly; ask here:

    from entitlements import engine
    engine.has(user, "royal_items")
    engine.value(user, "game_exp_bonus")     # 0 when it doesn't apply
"""
