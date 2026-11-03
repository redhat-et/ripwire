let { leaf, other } = require("../src/util");
test("x", () => {
  leaf = other; leaf(1);
});
