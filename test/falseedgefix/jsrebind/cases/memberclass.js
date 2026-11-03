let { Eng, Foo } = require("../src/eng");
Eng = Foo;
test("x", () => { Eng.run(); });
