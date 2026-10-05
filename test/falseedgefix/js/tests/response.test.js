'use strict'

const request = require('supertest')

function checkStatus (app) {
  return request(app.callback()).get('/')
}

module.exports = { checkStatus }
