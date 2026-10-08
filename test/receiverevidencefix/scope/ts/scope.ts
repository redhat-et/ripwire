// Review B4 (language neutrality): a binding that hides an outer typed binding of its name, and a type parameter named
// like a class. Tank and Barrel both define spill().
interface Spiller { spill(): void }
export class Tank implements Spiller { spill() {} }
export class Barrel implements Spiller { spill() {} }
export function arrowParam(tank: Tank, bs: Barrel[]) { bs.forEach((tank) => tank.spill()); }
export function forOf(tank: Tank, bs: Barrel[]) { for (const tank of bs) { tank.spill(); } }
export function blockLocal(tank: Tank, b: Barrel) { { const tank = b; tank.spill(); } }
export function catchParam(tank: Tank) { try { } catch (tank) { tank.spill(); } }
export function destructure(tank: Tank, p: [Barrel, Barrel]) { { const [tank] = p; tank.spill(); } }
export function typeParam<Tank extends Spiller>(t: Tank) { t.spill(); }
export class Box<Tank extends Spiller> {
  item: Tank;
  constructor(item: Tank) { this.item = item; }
  classTypeParam(t: Tank) { t.spill(); }
  typeParamField() { this.item.spill(); }
}
export function typedParam(t: Tank) { t.spill(); }
