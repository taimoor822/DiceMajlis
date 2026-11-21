from django.urls import path

from . import views

urlpatterns = [
    path("auth/guest/", views.guest_login),
    path("auth/register/", views.register),
    path("auth/login/", views.login),
    path("auth/save-account/", views.save_account),
    path("auth/password-reset/", views.password_reset_request),
    path("auth/password-reset/confirm/", views.password_reset_confirm),
    path("auth/refresh/", views.refresh),
    path("auth/logout/", views.logout),
    path("auth/logout-others/", views.logout_others),
    path("me/", views.me),
    path("auth/providers/", views.providers),
    path("auth/social/<str:provider>/", views.social_login),
    path("me/link/<str:provider>/", views.link_social),
    path("me/unlink/<str:provider>/", views.unlink_social),
]
