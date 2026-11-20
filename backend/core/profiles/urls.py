from django.urls import path

from . import views

urlpatterns = [
    path("profile/options/", views.profile_options),
    path("me/profile/", views.update_my_profile),
]
