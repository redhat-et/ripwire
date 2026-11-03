const m = require("../src/eng");
let Eng: typeof m.Eng = m.Eng;
test("x", () => {
  Eng = m.Foo; const a = new Eng();
});
