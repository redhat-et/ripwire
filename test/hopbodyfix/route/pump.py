from message import Message as Event
import queue


class Pump:
    def __init__(self, parent=None):
        self._queue = queue.Queue()
        self._parent = parent

    def post_message(self, message):
        if self._closed:
            return False
        self._queue.put_nowait(message)
        return True

    def _get_message(self):
        return self._queue.get()

    def _process_messages_loop(self):
        while not self._closed:
            message = self._get_message()
            self._dispatch_message(message)

    def _dispatch_message(self, message):
        if message.no_dispatch:
            return
        self.on_event(message)

    async def on_event(self, event: Event) -> None:
        self._on_message(event)

    def _on_message(self, message):
        handler_name = message.handler_name
        for method in self._get_dispatch_methods(handler_name, message):
            method(message)
        if message.bubble and self._parent is not None:
            self._parent.post_message(message)

    def _get_dispatch_methods(self, method_name, message):
        for cls in self.__class__.__mro__:
            method = cls.__dict__.get(method_name)
            if method is not None:
                yield method.__get__(self, cls)
