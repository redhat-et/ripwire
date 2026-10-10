const { Base, Widget, makeBase } = require('./shapes');

class Panel extends Base {
  typed() {
    const base = new Widget();
    return base.render();
  }

  untyped() {
    const base = makeBase();
    return base.render();
  }

  realSuper() {
    return super.render();
  }
}

module.exports = { Panel };
