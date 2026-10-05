'use strict'

// A test helper spelled like the supertest default export.
function request (req, res, app) {
  return { req, res, app }
}

module.exports = { request }
