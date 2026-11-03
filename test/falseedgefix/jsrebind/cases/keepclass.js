class Eng { z() {} }
Eng = require("../src/engc").Eng;
test("x", () => { const a = new Eng(); });
