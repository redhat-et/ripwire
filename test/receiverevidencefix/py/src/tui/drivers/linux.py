import os

from ..xterm_parser import XTermParser


class Driver:
    def run_input_thread(self, fd):
        """Aliases bound in the method and called from a nested def: an outside function and a constructed
        object's bound method."""
        parser = XTermParser()
        feed = parser.feed
        read = os.read

        def process_events(ready):
            for _ in ready:
                data = read(fd, 1024)
                for event in feed(data):
                    print(event)

        process_events([fd])
