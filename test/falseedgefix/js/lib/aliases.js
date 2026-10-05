'use strict'
const { stringify } = JSON
const fmt = makeFmt()
function makeFmt () { return (x) => x }
function a (o) { return stringify(o) }
function b (u) { return globalThis.fetch(u) }
function c (x) { return fmt(x) }
module.exports = { a, b, c }
