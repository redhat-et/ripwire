'use strict'
// Reflect and Atomics are globals: their get/add are never this file's functions of those names.
function get (obj, key) {
  return obj[key]
}

function add (a, b) {
  return a + b
}

function peek (obj) {
  return Reflect.get(obj, 'x')
}

function bump (arr) {
  return Atomics.add(arr, 0, 1)
}

module.exports = { get, add, peek, bump }
