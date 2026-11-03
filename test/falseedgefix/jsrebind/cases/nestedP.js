let { Eng, Foo } = require("../src/eng");
function g() {
  let Eng = Foo; Eng = Foo; const a = new Eng();
}
function h() { return new Eng(); }
