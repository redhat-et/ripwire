import Eng, * as ns from "../src/eng";
test("x", () => { Eng = ns.Foo; ns = 1; const a = new Eng(); });
