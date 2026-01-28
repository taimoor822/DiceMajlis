from django.shortcuts import render

# Create your views import random
import string

from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status

from .models import Room, Player
from .serializers import RoomSerializer, PlayerSerializer


def generate_room_code():
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))


@api_view(['POST'])
def create_room(request):
    max_players = request.data.get('max_players', 4)
    player_name = request.data.get('name', 'Player 1')
    color = request.data.get('color', 'red')

    # Create unique room code
    code = generate_room_code()
    while Room.objects.filter(code=code).exists():
        code = generate_room_code()

    room = Room.objects.create(
        code=code,
        max_players=max_players
    )

    # Create host player
    player = Player.objects.create(
        room=room,
        name=player_name,
        color=color,
        is_host=True
    )

    return Response({
        'room': RoomSerializer(room).data,
        'player': PlayerSerializer(player).data
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
def join_room(request):
    code = request.data.get('code')
    player_name = request.data.get('name', 'Player')
    color = request.data.get('color', 'blue')

    if not code:
        return Response(
            {'error': 'Room code is required'},
            status=status.HTTP_400_BAD_REQUEST
        )

    try:
        room = Room.objects.get(code=code)
    except Room.DoesNotExist:
        return Response(
            {'error': 'Room not found'},
            status=status.HTTP_404_NOT_FOUND
        )

    if room.is_started:
        return Response(
            {'error': 'Game already started'},
            status=status.HTTP_400_BAD_REQUEST
        )

    if room.players.count() >= room.max_players:
        return Response(
            {'error': 'Room is full'},
            status=status.HTTP_400_BAD_REQUEST
        )

    player = Player.objects.create(
        room=room,
        name=player_name,
        color=color,
        is_host=False
    )

    return Response({
        'room': RoomSerializer(room).data,
        'player': PlayerSerializer(player).data
    }, status=status.HTTP_200_OK)
