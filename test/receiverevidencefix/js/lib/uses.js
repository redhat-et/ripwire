'use strict'
// Near misses: receivers proven by construction, an import alias, and a relative module object.
const { Schemas: Store } = { Schemas: require('./schemas') }
const Schemas = require('./schemas')
const Application = require('./application')
const replies = require('./reply')

function build () {
  const app = new Application()
  app.onerror(new Error('built'))
  const s = new Schemas()
  return s.listSchemas()
}

function viaModule (reply) {
  return replies.respondWith(reply, 'ok')
}

function make () {
  return Application.create()
}

module.exports = { build, viaModule, make, Store }
