class Registry {
  constructor(options) {
    this.options = options;
    this.v0 = zeta1();
    this.v1 = zeta2();
    this.v2 = zeta3();
    this.v3 = zeta4();
    this.v4 = zeta5();
    this.v5 = zeta6();
    this.v6 = zeta7();
    this.v7 = zeta8();
    this.v8 = zeta9();
    this.v9 = alpha1();
    this.v10 = alpha2();
    this.v11 = alpha3();
    this.v12 = alpha4();
    this.v13 = alpha5();
    this.v14 = alpha6();
    this.v15 = alpha7();
    this.v16 = alpha8();
    this.v17 = alpha9();
  }

  create(name) {
    const entry = Object.create(this.options);
    entry.name = name;
    return entry;
  }
}

module.exports = Registry;
