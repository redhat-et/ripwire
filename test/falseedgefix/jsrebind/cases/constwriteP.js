const { Eng, Foo } = require("../src/eng");
test("x", () => { try { Eng = Foo; } catch (e) {} const a = new Eng(); });
