function makeStore(options) {
  return { options };
}

class Registry {
  create(name) {
    const entry = Object.create(makeStore(name));
    entry.name = name;
    return entry;
  }
}

module.exports = Registry;
