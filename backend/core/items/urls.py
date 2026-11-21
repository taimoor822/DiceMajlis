from django.urls import path

from . import views

urlpatterns = [
    path("me/items/", views.my_items),
    path("me/items/equip/", views.equip),
]
