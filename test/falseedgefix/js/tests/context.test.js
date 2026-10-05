'use strict'

const { request } = require('../helpers/context')
const myJson = require('../lib/query')

// True edges: a destructured relative require, and a receiver bound to a relative module.
function makeCtx (app) {
  return request({}, {}, app)
}

function encodeQuery (obj) {
  return myJson.stringify(obj)
}

module.exports = { makeCtx, encodeQuery }
