'use strict'
class Schemas {
  constructor () {
    this.store = {}
  }

  listSchemas () {
    return Object.keys(this.store)
  }
}
module.exports = Schemas
