from handlers import call_handler, not_found


class Router:
    def __init__(self):
        self.routes = {}

    def add_route(self, path, handler):
        self.routes[path] = handler

    def dispatch(self, request):
        handler = self.match_route(request.path)
        if handler is None:
            return not_found(request)
        return call_handler(handler, request)

    def match_route(self, path):
        for prefix, handler in self.routes.items():
            if path.startswith(prefix):
                return handler
        return None
