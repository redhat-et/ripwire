function makeStore(options) {
  return { options, items: [] };
}

function makeLogger() {
  return console;
}

class Registry {
  constructor(options) {
    this.store = makeStore(options);
    this.logger = makeLogger();
    this.count = 0;
  }

  create(name) {
    const entry = Object.create(this.store);
    entry.name = name;
    return entry;
  }
}

module.exports = Registry;
