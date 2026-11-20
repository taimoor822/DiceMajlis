from django.urls import path

from . import views

urlpatterns = [
    path("rewards/daily/", views.daily_status),
    path("rewards/daily/claim/", views.daily_claim),
]
