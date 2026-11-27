class Ledger:
    def post_entry(self, e):
        return e


def h01(x):
    return x.post_entry(0)


def h02(led: Ledger):
    return led.post_entry(2)


def h03(led: Ledger):
    return led.post_entry(3)


def h04(led: Ledger):
    return led.post_entry(4)


def h05(led: Ledger):
    return led.post_entry(5)


def h06(led: Ledger):
    return led.post_entry(6)


def h07(led: Ledger):
    return led.post_entry(7)


def h08(led: Ledger):
    return led.post_entry(8)


def h09(led: Ledger):
    return led.post_entry(9)


def h10(led: Ledger):
    return led.post_entry(10)


def h11(led: Ledger):
    return led.post_entry(11)


def h12(led: Ledger):
    return led.post_entry(12)


def h13(led: Ledger):
    return led.post_entry(13)


def h14(led: Ledger):
    return led.post_entry(14)


def h15(led: Ledger):
    return led.post_entry(15)


def h16(led: Ledger):
    return led.post_entry(16)


def zz_hidden(led: Ledger):
    return led.post_entry(99)


def g01_0():
    return h01(Ledger())


def g01_1():
    return h01(Ledger())


def g02_0():
    return h02(Ledger())


def g02_1():
    return h02(Ledger())


def g03_0():
    return h03(Ledger())


def g03_1():
    return h03(Ledger())


def g04_0():
    return h04(Ledger())


def g04_1():
    return h04(Ledger())


def g05_0():
    return h05(Ledger())


def g05_1():
    return h05(Ledger())


def g06_0():
    return h06(Ledger())


def g06_1():
    return h06(Ledger())


def g07_0():
    return h07(Ledger())


def g07_1():
    return h07(Ledger())


def g08_0():
    return h08(Ledger())


def g08_1():
    return h08(Ledger())


def g09_0():
    return h09(Ledger())


def g09_1():
    return h09(Ledger())


def g10_0():
    return h10(Ledger())


def g10_1():
    return h10(Ledger())


def g11_0():
    return h11(Ledger())


def g11_1():
    return h11(Ledger())


def g12_0():
    return h12(Ledger())


def g12_1():
    return h12(Ledger())


def g13_0():
    return h13(Ledger())


def g13_1():
    return h13(Ledger())


def g14_0():
    return h14(Ledger())


def g14_1():
    return h14(Ledger())


def g15_0():
    return h15(Ledger())


def g15_1():
    return h15(Ledger())


def g16_0():
    return h16(Ledger())


def g16_1():
    return h16(Ledger())


def reach_both():
    h01(None)
    return zz_hidden(Ledger())


def r0():
    return reach_both()


def r1():
    return reach_both()


def r2():
    return reach_both()


def r3():
    return reach_both()


def r4():
    return reach_both()

