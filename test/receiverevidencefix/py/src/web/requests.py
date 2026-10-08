class HTTPConnection:
    """self._send holds the ASGI send callable passed in; the nested _send elsewhere is never it."""

    def __init__(self, scope, receive, send):
        self.scope = scope
        self._receive = receive
        self._send = send

    async def send_json(self, message):
        await self._send(message)
