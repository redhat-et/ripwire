// The two SIDES of a class lookup, typed: the class object reaches its static members, an instance the others.
export class Meter {
  static read(): number { return 1 }
  read(): number { return 2 }
}
export function onClass(): number { return Meter.read() }
export function onTyped(m: Meter): number { return m.read() }
