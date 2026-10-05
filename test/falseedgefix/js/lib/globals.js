'use strict'

// Every call here is on a global object; this file requires nothing.
function summarize (obj, a, b) {
  console.log(Object.keys(obj))
  const m = Math.max(a, b)
  const list = Array.from([m])
  return Promise.resolve(list)
}

module.exports = { summarize }
