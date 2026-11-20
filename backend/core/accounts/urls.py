from django.urls import path

from . import views

urlpatterns = [
    path("auth/guest/", views.guest_login),
    path("auth/refresh/", views.refresh),
    path("auth/logout/", views.logout),
    path("auth/logout-others/", views.logout_others),
    path("me/", views.me),
]
