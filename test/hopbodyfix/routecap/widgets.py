from message import Message
from pump import Pump


def leaf(x):
    return x


class Tick(Message):
    pass


class Button(Pump):
    class Pressed(Message):
        pass

    def press(self):
        self.post_message(self.Pressed())


class Worker(Pump):
    class Changed(Message, namespace="worker"):
        pass

    def change(self):
        self.post_message(Worker.Changed())


class Form(Pump):
    def on_button_pressed(self, m):
        return leaf(m)

    def on_worker_changed(self, m):
        return m

    def on_tick(self, m):
        return leaf(m)


def log(m):
    return m


class Clock(Pump):
    def tick(self):
        self.post_message(Tick())

    def poke(self):
        msg = Tick()
        self.post_message(msg)

    def note(self):
        log(Tick())
