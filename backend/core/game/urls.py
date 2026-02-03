from django.urls import path

from .views import create_room, join_room, move_token, roll_dice, start_game

urlpatterns = [
    path('create-room/', create_room),
    path('join-room/', join_room),
    path('start-game/', start_game),
    path('roll-dice/', roll_dice),
    path('move-token/', move_token),

]
