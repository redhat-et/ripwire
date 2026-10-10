const { Obj } = require('./object');
module.exports = class Loader extends Obj {
  resolve(from, to) { return to; }
};
