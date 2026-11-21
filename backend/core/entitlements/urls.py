from django.urls import path

from . import views

urlpatterns = [path("me/entitlements/", views.my_entitlements)]
