'use strict'
// A request delegate: ctx.get(field) reaches this get through delegation, never by a static edge.
module.exports = {
  get (field) {
    const header = this.header
    return header[field] || ''
  }
}
