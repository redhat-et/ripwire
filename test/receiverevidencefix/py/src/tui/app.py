from .screen import Screen


class App:
    """A non-self receiver in the class's own file: the file defining App is no evidence."""

    def __init__(self):
        self._screen_stack = [Screen()]

    @property
    def screen(self):
        """The top of the screen stack: a property, so `self.screen` carries no receiver evidence."""
        return self._screen_stack[-1]

    def refresh(self):
        return False

    def get_screen(self, name):
        return Screen()

    def switch_mode(self, name):
        mode_screen = self.get_screen(name)
        mode_screen.refresh()

    def repaint(self):
        self.refresh()
        self.screen.refresh()

    def repaint_screen(self):
        self.screen.refresh()
