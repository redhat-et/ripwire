let { Eng, Foo } = require("../src/eng");
function g() {
  Eng = Foo; const a = new Eng();
}
function h() { return new Eng(); }
