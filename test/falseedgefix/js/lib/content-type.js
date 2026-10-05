'use strict'

// A class with a static factory spelled like Buffer.from.
class ContentType {
  constructor (value) { this.value = value }
  static from (headerValue) { return new ContentType(headerValue) }
}

module.exports = { ContentType }
