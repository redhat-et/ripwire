class Rig { fire() { return 1; } }
let rig;
test("x", () => { rig = new Rig(); rig.fire(); });
