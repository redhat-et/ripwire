from ui.css.match import *
from ui.worker import Worker
from ui.text import format


def mymax(a, b):
    return a


def make():
    return mymax


handler = make()


def use_star(s, n):
    # match comes from the star import: the module function, not a method
    return match(s, n)


def use_var(a, b):
    return handler(a, b)


def build():
    return Worker()


def fmt(v):
    return format(v)
