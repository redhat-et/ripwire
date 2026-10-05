'use strict'

// The request prototype: an accessor spelled like the global URL constructor.
module.exports = {
  get URL () {
    return this.originalUrl
  },
  get host () {
    const host = this.get('Host')
    return new URL(`http://${host}`).host
  },
  get (field) {
    return this.headers[field]
  }
}
