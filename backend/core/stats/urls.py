from django.urls import path

from . import views

urlpatterns = [path("me/stats/", views.my_stats)]
