let { Eng, Foo } = require("../src/eng");
const o = {};
test("x", () => { o.Eng = Foo; const z = { Eng }; const a = new Eng(); });
function onSendEnd (reply) {
  let run = '';
  run += ' ';
  reply.run(run.trim());
}
