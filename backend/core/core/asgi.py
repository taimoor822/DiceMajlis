import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.auth import AuthMiddlewareStack

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'core.settings')

# ✅ FIRST initialize Django
django_asgi_app = get_asgi_application()

# ✅ ONLY NOW import routing
import game.routing
from django.conf import settings

# Server-side turn timer (auto-play idle players). Only ASGI servers import this
# module, so management commands and tests never start it.
if settings.GAME_TIMER_IN_PROCESS:
    from game.timers import start_in_background
    start_in_background(settings.GAME_TIMER_INTERVAL_SECONDS)

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": AuthMiddlewareStack(
        URLRouter(
            game.routing.websocket_urlpatterns
        )
    ),
})
