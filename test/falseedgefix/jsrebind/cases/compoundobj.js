let { Eng, Foo } = require("../src/eng");
test("x", () => {
  ({ Eng } = { Eng: Foo }); const a = new Eng();
});
