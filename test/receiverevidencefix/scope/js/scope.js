// Review B4 (language neutrality): a binding that hides an outer constructed local of its name.
export class Tank { spill() {} }
export class Barrel { spill() {} }
export function arrowParam(bs) { const tank = new Tank(); bs.forEach((tank) => tank.spill()); }
export function forOf(bs) { const tank = new Tank(); for (const tank of bs) { tank.spill(); } }
export function catchParam() { const tank = new Tank(); try { } catch (tank) { tank.spill(); } }
export function blockOutside(b) { const tank = new Tank(); { const tank = b; } tank.spill(); }
export function reassign(b) { let tank = new Tank(); tank = b; tank.spill(); }
export function constructed() { const t = new Tank(); t.spill(); }
