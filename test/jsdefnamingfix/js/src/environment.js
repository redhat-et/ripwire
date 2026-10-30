class Environment {
  render(name) {
    return jdnEnvHelper(name)
  }
}

class Template {
  render(ctx) {
    return jdnTplHelper(ctx)
  }
}

module.exports = { Environment, Template }
