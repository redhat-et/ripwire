import typing
from typing import Optional

import requests
from pkg.sub import checker
from pkg.sub.checker import Manager
from pkg.sub.strat import FastStrategy, Strategy


class AppA:
    def __init__(self):
        self.m1: checker.Manager | None = None
        self.m2: Manager | None = None
        self.m3 = None
        self.m4: checker.Manager = None
        self.m5: Optional[Manager] = None
        self.m6: typing.Optional[checker.Manager] = None
        self.ext: requests.Session | None = None
        self.both: Manager | AppA | None = None
        self.both2: Manager | AppA = None

    def make(self):
        self.m3 = checker.Manager()

    def go1(self):
        self.m1.start()

    def go2(self):
        self.m2.start()

    def go3(self):
        self.m3.start()

    def go4(self):
        self.m4.start()

    def go5(self):
        self.m5.start()

    def go6(self):
        self.m6.start()

    def goExt(self):
        self.ext.start()

    def goBoth(self):
        self.both.start()

    def goBoth2(self):
        self.both2.start()

    def start(self):
        return 0


def go8():
    a = checker.Manager()
    a.start()


def goExtLocal():
    s = requests.Manager()
    s.start()


def goParam(p: Manager | None):
    p.start()


class AppC:
    def __init__(self):
        self.s10: Strategy = FastStrategy()
        self.s11: Strategy = None

    def go10(self):
        self.s10.run()

    def go11(self):
        self.s11.run()
