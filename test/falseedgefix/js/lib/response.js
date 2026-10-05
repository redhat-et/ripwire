'use strict'

const destroy = require('destroy')
const { ContentType } = require('./content-type')

module.exports = {
  get length () {
    const body = this.body
    return Buffer.byteLength(JSON.stringify(body))
  },
  redirect (url) {
    url = new URL(url).toString()
    this.set('Location', url)
  },
  finish (stream) {
    destroy(stream)
  },
  encode (payload) {
    return Buffer.isBuffer(payload) ? payload : Buffer.from(payload)
  },
  parseType () {
    return ContentType.from(this.type)
  },
  set (field, val) {
    this.headers[field] = val
  }
}
