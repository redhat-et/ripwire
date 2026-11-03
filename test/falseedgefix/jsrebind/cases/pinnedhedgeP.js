class Tank { drip() { return 1; } }
class Barrel { drip() { return 2; } }
export function reassign(b) { let tank = new Tank(); tank = b; tank.drip(); }
