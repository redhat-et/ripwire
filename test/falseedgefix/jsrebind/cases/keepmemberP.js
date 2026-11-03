var Eng;
if (typeof require !== "undefined") { Eng = require("../src/eng").Eng; } else { Eng = window.lib.Eng; }
test("x", () => { const a = new Eng(); });
