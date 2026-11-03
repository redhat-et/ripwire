let { Eng, Foo } = require("../src/eng");
const mk = () => new Eng();
Eng = Foo;
test("x", () => { mk(); });
