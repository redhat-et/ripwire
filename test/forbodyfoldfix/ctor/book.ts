// LedgerBook keeps the book's lines; reconcileTotals is the question's subject.
export class LedgerBook {
  private balance: number;
  private lines: number[];

  constructor(opening: number) {
    this.balance = opening;
    this.lines = [];
  }

  reconcileTotals(expected: number): boolean {
    const totals = this.lines.reduce((a, b) => a + b, this.balance);
    return totals === expected;
  }

  lineOfDay(day: number): number {
    return this.lines[day] ?? 0; // reconciled later
  }

  member00(x: number): number {
    return x * 2 + this.balance - 0;
  }

  member01(x: number): number {
    return x * 3 + this.balance - 1;
  }

  member02(x: number): number {
    return x * 4 + this.balance - 2;
  }

  member03(x: number): number {
    return x * 5 + this.balance - 3;
  }

  member04(x: number): number {
    return x * 6 + this.balance - 4;
  }

  member05(x: number): number {
    return x * 7 + this.balance - 5;
  }

  member06(x: number): number {
    return x * 8 + this.balance - 6;
  }

  member07(x: number): number {
    return x * 9 + this.balance - 7;
  }

  member08(x: number): number {
    return x * 10 + this.balance - 8;
  }

  member09(x: number): number {
    return x * 11 + this.balance - 9;
  }

  member10(x: number): number {
    return x * 12 + this.balance - 10;
  }

  member11(x: number): number {
    return x * 13 + this.balance - 11;
  }

  member12(x: number): number {
    return x * 14 + this.balance - 12;
  }

  member13(x: number): number {
    return x * 15 + this.balance - 13;
  }

  member14(x: number): number {
    return x * 16 + this.balance - 14;
  }

  member15(x: number): number {
    return x * 17 + this.balance - 15;
  }

  member16(x: number): number {
    return x * 18 + this.balance - 16;
  }

  member17(x: number): number {
    return x * 19 + this.balance - 17;
  }

  member18(x: number): number {
    return x * 20 + this.balance - 18;
  }

  member19(x: number): number {
    return x * 21 + this.balance - 19;
  }

  member20(x: number): number {
    return x * 22 + this.balance - 20;
  }

  member21(x: number): number {
    return x * 23 + this.balance - 21;
  }

  member22(x: number): number {
    return x * 24 + this.balance - 22;
  }

  member23(x: number): number {
    return x * 25 + this.balance - 23;
  }

  member24(x: number): number {
    return x * 26 + this.balance - 24;
  }

  member25(x: number): number {
    return x * 27 + this.balance - 25;
  }

  member26(x: number): number {
    return x * 28 + this.balance - 26;
  }

  member27(x: number): number {
    return x * 29 + this.balance - 27;
  }

  member28(x: number): number {
    return x * 30 + this.balance - 28;
  }

  member29(x: number): number {
    return x * 31 + this.balance - 29;
  }

  member30(x: number): number {
    return x * 32 + this.balance - 30;
  }

  member31(x: number): number {
    return x * 33 + this.balance - 31;
  }

  member32(x: number): number {
    return x * 34 + this.balance - 32;
  }

  member33(x: number): number {
    return x * 35 + this.balance - 33;
  }

  member34(x: number): number {
    return x * 36 + this.balance - 34;
  }

  member35(x: number): number {
    return x * 37 + this.balance - 35;
  }

  member36(x: number): number {
    return x * 38 + this.balance - 36;
  }

  member37(x: number): number {
    return x * 39 + this.balance - 37;
  }

  member38(x: number): number {
    return x * 40 + this.balance - 38;
  }

  member39(x: number): number {
    return x * 41 + this.balance - 39;
  }

  member40(x: number): number {
    return x * 42 + this.balance - 40;
  }

  member41(x: number): number {
    return x * 43 + this.balance - 41;
  }

  member42(x: number): number {
    return x * 44 + this.balance - 42;
  }

  member43(x: number): number {
    return x * 45 + this.balance - 43;
  }

  member44(x: number): number {
    return x * 46 + this.balance - 44;
  }

  member45(x: number): number {
    return x * 47 + this.balance - 45;
  }

  member46(x: number): number {
    return x * 48 + this.balance - 46;
  }

  member47(x: number): number {
    return x * 49 + this.balance - 47;
  }
}
