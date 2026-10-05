'use strict'

const qs = require('qs')
const { parse } = require('cookie')

// Both calls reach packages outside the tree, required by bare specifiers.
function toQuery (obj) {
  return qs.stringify(obj)
}

function readCookies (header) {
  return parse(header)
}

module.exports = { toQuery, readCookies }
