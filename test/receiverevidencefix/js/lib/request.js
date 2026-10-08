'use strict'
// A dynamic builtin receiver in the defining file: WeakMap .set/.get never reach the accessors below.
const kCache = Symbol('cache')

function Request (headers) {
  this.headersStore = headers
  this[kCache] = new WeakMap()
}

Object.defineProperties(Request.prototype, {
  headers: {
    get () {
      return this.headersStore
    },
    set (headers) {
      this.headersStore = headers
    }
  }
})

Request.prototype.compile = function (schema, fn) {
  this[kCache].set(schema, fn)
  return this[kCache].get(schema)
}

module.exports = Request
