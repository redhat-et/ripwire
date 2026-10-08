'use strict'
// A closure named like Reply.prototype.send: only its own enclosing function can call it.
function sendTrailer (reply, value) {
  function send (v) {
    reply.res.addTrailers(v)
  }
  send(value)
}
module.exports = { sendTrailer }
