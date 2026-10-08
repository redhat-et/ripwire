'use strict'
class Response {
  append (field, val) {
    this.headers = this.headers || {}
    this.headers[field] = val
  }
}
module.exports = Response
