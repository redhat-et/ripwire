let { Eng, Foo } = require("../src/eng");
test("x", () => { for (let i = 0; i < 2; i++) { const a = new Eng(); Eng = Foo; } });
