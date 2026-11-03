const { Eng: E } = require("../src/eng");
function Eng() { return 1; }
Eng = E;
test("x", () => { const a = new Eng(); });
