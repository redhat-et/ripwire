'use strict'
// An object-literal module: `this.ctx` is a request context, so this.ctx.get() is never this module's own get.
module.exports = {
  get (field) {
    return this.header[field]
  },

  back () {
    return this.ctx.get('Referrer')
  }
}
