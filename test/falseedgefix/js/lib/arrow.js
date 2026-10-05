'use strict'

// A const-bound arrow function: a bare call in this file reaches it.
const normalize = (s) => s.trim()

function clean (s) {
  return normalize(s)
}

module.exports = { clean }
