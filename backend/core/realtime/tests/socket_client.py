"""
A small socket test client (what channels.testing.WebsocketCommunicator does),
built on asgiref so the tests don't need the daphne server package.
"""

import json

from asgiref.testing import ApplicationCommunicator


class SocketClient(ApplicationCommunicator):
    def __init__(self, application, path: str):
        super().__init__(application, {
            "type": "websocket",
            "path": path,
            "raw_path": path.encode(),
            "query_string": b"",
            "headers": [],
            "subprotocols": [],
        })

    async def connect(self, timeout=1):
        await self.send_input({"type": "websocket.connect"})
        response = await self.receive_output(timeout)
        if response["type"] == "websocket.close":
            return False, response.get("code", 1000)
        return True, response.get("subprotocol")

    async def send_to(self, text_data: str):
        await self.send_input({"type": "websocket.receive", "text": text_data})

    async def send_json_to(self, data):
        await self.send_to(json.dumps(data))

    async def receive_json_from(self, timeout=1):
        response = await self.receive_output(timeout)
        assert response["type"] == "websocket.send", response
        return json.loads(response["text"])

    async def disconnect(self, code=1000, timeout=1):
        await self.send_input({"type": "websocket.disconnect", "code": code})
        await self.wait(timeout)
