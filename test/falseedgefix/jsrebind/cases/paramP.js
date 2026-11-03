let { Eng, Foo } = require("../src/eng");
function g(Eng) { Eng = Foo; return Eng; }
test("x", () => { const a = new Eng(); });
