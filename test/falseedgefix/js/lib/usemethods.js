'use strict'

const { tidy } = require('./methods')

// A true edge: a name destructured from a relative require may name an object's method.
function cleanAll (s) {
  return tidy(s)
}

module.exports = { cleanAll }
