let { Eng, Foo } = require("../src/eng");
test("x", () => {
  if (process.env.C) Eng = Foo;
  const a = new Eng();
});
