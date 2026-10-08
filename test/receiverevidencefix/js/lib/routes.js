'use strict'
// A router from an outside package and a builtin Set, beside the instance shorthands of those names.
const FindMyWay = require('find-my-way')

const instance = {
  all: function _all (url, fn) { return fn },
  delete: function _delete (url, fn) { return fn }
}

function fallback (handler) {
  const router = FindMyWay({ defaultRoute: handler })
  router.all('/*', handler)
}

function forget (connections, conn) {
  connections.delete(conn)
}

module.exports = { instance, fallback, forget }
