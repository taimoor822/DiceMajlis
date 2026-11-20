from django.urls import path

from . import views

urlpatterns = [
    path("wallet/", views.wallet),
    path("wallet/transactions/", views.transactions),
]
