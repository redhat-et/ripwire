'use strict'

// A file-local binding named JSON shadows the global: its stringify call is the in-repo one.
const JSON = require('./query')

function emit (obj) {
  return JSON.stringify(obj)
}

// A same-file function spelled like a global: a bare call reaches it.
function fetch (url) {
  return url
}

function load (url) {
  return fetch(url)
}

module.exports = { emit, load }
