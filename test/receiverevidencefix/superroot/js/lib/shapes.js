class Base {
  render() { return 'base'; }
}

class Widget {
  render() { return 'widget'; }
}

function makeBase() { return {}; }

module.exports = { Base, Widget, makeBase };
