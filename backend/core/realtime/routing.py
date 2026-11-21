from django.urls import re_path

from .consumers import RealtimeConsumer

websocket_urlpatterns = [
    re_path(r"^ws/v1/$", RealtimeConsumer.as_asgi()),
]
