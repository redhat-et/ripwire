class ServerErrorMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        async def _send(message):
            await send(message)

        await self.app(scope, receive, _send)
