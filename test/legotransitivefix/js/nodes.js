// The nunjucks node shape: a class FACTORY call names the class it makes.
const { Obj } = require('./object');
class Node extends Obj {
  init(lineno) { this.lineno = lineno; }
}
const Value = Node.extend('Value', { fields: ['value'] });
const BinOp = Node.extend('BinOp', { fields: ['left', 'right'] });
var Add = BinOp.extend('Add');
const Sub = BinOp.extend("Sub");
// near misses: none of these is a class
const settings = Node.extend({}, { a: 1 });
const Renamed = Node.extend('Other');
const Merged = Node.merge('Merged');
const Spread = Node.extend(...parts);
function local() {
  const Inner = Node.extend('Inner');
  return Inner;
}
module.exports = { Node, Value, BinOp, Add, Sub, settings, Renamed, Merged, Spread, local };
