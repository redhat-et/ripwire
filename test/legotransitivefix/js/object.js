class Obj {
  static extend(name, props) {
    return class extends this {};
  }
}
module.exports = { Obj };
