'use strict'
// Near miss: super.listSchemas() reaches the superclass's method.
const Schemas = require('./schemas')

class Listing extends Schemas {
  list () {
    return super.listSchemas()
  }
}
module.exports = Listing
