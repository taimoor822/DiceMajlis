from django.urls import path

from . import views

urlpatterns = [path("me/achievements/", views.my_achievements)]
