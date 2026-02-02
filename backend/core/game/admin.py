from django.contrib import admin
from .models import Room, Player, Game, Turn

admin.site.register(Room)
admin.site.register(Player)
admin.site.register(Game)
admin.site.register(Turn)