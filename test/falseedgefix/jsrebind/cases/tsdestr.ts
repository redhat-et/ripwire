let { Eng, Foo }: { Eng: any; Foo: any } = require("../src/eng");
test("x", () => {
  Eng = Foo; const a = new Eng();
});
