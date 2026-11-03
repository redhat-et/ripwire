let Eng;
const mod = require("../src/eng");
beforeEach(() => { ({ Eng = mod.Foo } = mod); });
test("x", () => { const a = new Eng(); });
