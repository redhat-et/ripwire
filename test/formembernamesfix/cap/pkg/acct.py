"""The ledger book: twenty-nine entry kinds, one method each."""


class LedgerBook:
    """Records ledger entries."""

    def __init__(self):
        self.lines = []

    def entry00(self, amount):
        """Add one line of kind 00 with its amount and a running sum."""
        self.lines.append((0, amount))
        return sum(a for _, a in self.lines)

    def entry01(self, amount):
        """Add one line of kind 01 with its amount and a running sum."""
        self.lines.append((1, amount))
        return sum(a for _, a in self.lines)

    def entry02(self, amount):
        """Add one line of kind 02 with its amount and a running sum."""
        self.lines.append((2, amount))
        return sum(a for _, a in self.lines)

    def entry03(self, amount):
        """Add one line of kind 03 with its amount and a running sum."""
        self.lines.append((3, amount))
        return sum(a for _, a in self.lines)

    def entry04(self, amount):
        """Add one line of kind 04 with its amount and a running sum."""
        self.lines.append((4, amount))
        return sum(a for _, a in self.lines)

    def entry05(self, amount):
        """Add one line of kind 05 with its amount and a running sum."""
        self.lines.append((5, amount))
        return sum(a for _, a in self.lines)

    def entry06(self, amount):
        """Add one line of kind 06 with its amount and a running sum."""
        self.lines.append((6, amount))
        return sum(a for _, a in self.lines)

    def entry07(self, amount):
        """Add one line of kind 07 with its amount and a running sum."""
        self.lines.append((7, amount))
        return sum(a for _, a in self.lines)

    def entry08(self, amount):
        """Add one line of kind 08 with its amount and a running sum."""
        self.lines.append((8, amount))
        return sum(a for _, a in self.lines)

    def entry09(self, amount):
        """Add one line of kind 09 with its amount and a running sum."""
        self.lines.append((9, amount))
        return sum(a for _, a in self.lines)

    def entry10(self, amount):
        """Add one line of kind 10 with its amount and a running sum."""
        self.lines.append((10, amount))
        return sum(a for _, a in self.lines)

    def entry11(self, amount):
        """Add one line of kind 11 with its amount and a running sum."""
        self.lines.append((11, amount))
        return sum(a for _, a in self.lines)

    def entry12(self, amount):
        """Add one line of kind 12 with its amount and a running sum."""
        self.lines.append((12, amount))
        return sum(a for _, a in self.lines)

    def entry13(self, amount):
        """Add one line of kind 13 with its amount and a running sum."""
        self.lines.append((13, amount))
        return sum(a for _, a in self.lines)

    def entry14(self, amount):
        """Add one line of kind 14 with its amount and a running sum."""
        self.lines.append((14, amount))
        return sum(a for _, a in self.lines)

    def entry15(self, amount):
        """Add one line of kind 15 with its amount and a running sum."""
        self.lines.append((15, amount))
        return sum(a for _, a in self.lines)

    def entry16(self, amount):
        """Add one line of kind 16 with its amount and a running sum."""
        self.lines.append((16, amount))
        return sum(a for _, a in self.lines)

    def entry17(self, amount):
        """Add one line of kind 17 with its amount and a running sum."""
        self.lines.append((17, amount))
        return sum(a for _, a in self.lines)

    def entry18(self, amount):
        """Add one line of kind 18 with its amount and a running sum."""
        self.lines.append((18, amount))
        return sum(a for _, a in self.lines)

    def entry19(self, amount):
        """Add one line of kind 19 with its amount and a running sum."""
        self.lines.append((19, amount))
        return sum(a for _, a in self.lines)

    def entry20(self, amount):
        """Add one line of kind 20 with its amount and a running sum."""
        self.lines.append((20, amount))
        return sum(a for _, a in self.lines)

    def entry21(self, amount):
        """Add one line of kind 21 with its amount and a running sum."""
        self.lines.append((21, amount))
        return sum(a for _, a in self.lines)

    def entry22(self, amount):
        """Add one line of kind 22 with its amount and a running sum."""
        self.lines.append((22, amount))
        return sum(a for _, a in self.lines)

    def entry23(self, amount):
        """Add one line of kind 23 with its amount and a running sum."""
        self.lines.append((23, amount))
        return sum(a for _, a in self.lines)

    def entry24(self, amount):
        """Add one line of kind 24 with its amount and a running sum."""
        self.lines.append((24, amount))
        return sum(a for _, a in self.lines)

    def entry25(self, amount):
        """Add one line of kind 25 with its amount and a running sum."""
        self.lines.append((25, amount))
        return sum(a for _, a in self.lines)

    def entry26(self, amount):
        """Add one line of kind 26 with its amount and a running sum."""
        self.lines.append((26, amount))
        return sum(a for _, a in self.lines)

    def entry27(self, amount):
        """Add one line of kind 27 with its amount and a running sum."""
        self.lines.append((27, amount))
        return sum(a for _, a in self.lines)

    def entry28(self, amount):
        """Add one line of kind 28 with its amount and a running sum."""
        self.lines.append((28, amount))
        return sum(a for _, a in self.lines)


def open_ledger():
    return LedgerBook()
