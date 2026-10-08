'use strict'
// Near miss: a file-local binding named Reflect IS the relative module, so its get is a real edge.
const Reflect = require('./reflect')

function look (obj) {
  return Reflect.get(obj, 'k')
}
module.exports = { look }
