from django.urls import path
from .views import create_room, join_room, start_game, roll_dice

urlpatterns = [
    path('create-room/', create_room),
    path('join-room/', join_room),
    path('start-game/', start_game),
    path('roll-dice/', roll_dice),

]
