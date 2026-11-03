class Box { static make() { return 1; } }
class Crate { static make() { return 2; } }
let Pack = Box;
Pack = Crate;
test("x", () => { Pack.make(); });
