'use strict'
function runParser (req, body) {
  function done (error, parsed) {
    req.body = error ? null : parsed
  }
  done(null, body)
}
module.exports = { runParser }
