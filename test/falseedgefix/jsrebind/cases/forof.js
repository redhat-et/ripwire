let { Eng, Foo } = require("../src/eng");
test("x", () => { for (Eng of [Foo]) { const a = new Eng(); } });
