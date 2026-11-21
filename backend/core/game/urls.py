from django.urls import path

from .views import (
    create_room,
    game_catalog,
    invites,
    join_room,
    leave_room,
    move_token,
    roll_dice,
    room_options,
    start_game,
)

urlpatterns = [
    path('catalog/', game_catalog),
    path('room-options/', room_options),
    path('create-room/', create_room),
    path('join-room/', join_room),
    path('start-game/', start_game),
    path('roll-dice/', roll_dice),
    path('move-token/', move_token),
    path('leave-room/', leave_room),
    path('invites/', invites),
]
