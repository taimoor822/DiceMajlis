from django.urls import path
from .views import create_room, join_room

urlpatterns = [
    path('create-room/', create_room),
    path('join-room/', join_room),
]