'use strict'

// Helpers spelled like members of the global console, Math, Object, Promise and Array objects.
function log (msg) { return msg }
function max (a, b) { return a > b ? a : b }
function keys (o) { return [o] }
function resolve (v) { return v }
module.exports = { log, max, keys, resolve }
