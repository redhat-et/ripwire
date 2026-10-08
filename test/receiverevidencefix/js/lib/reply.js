'use strict'
// Promise .then, stream .on, a parameter callback and a chained send, beside in-repo names they never reach.
function Reply (res) {
  this.res = res
}

Reply.prototype.send = function (payload) {
  this.res.end(payload)
  return this
}

Reply.prototype.code = function (n) {
  this.res.statusCode = n
  return this
}

Reply.prototype.then = function (fulfilled, rejected) {
  return Promise.resolve(this).then(fulfilled, rejected)
}

function awaitResult (result, cb) {
  return result.then((v) => cb(null, v), cb)
}

function pipePayload (payload, onEnd) {
  payload.on('error', onEnd)
  payload.on('end', onEnd)
}

function writePayload (payload, done) {
  payload.write('x')
  done()
}

function notFound (reply) {
  reply.code(404).send('missing')
}

function respondWith (reply, body) {
  reply.send(body)
}

// Near miss for --impact inheritance: `direct` reaches send through a construction (proven), so `both`
// is reached at d=2 by a proven path as well as through respondWith's name-only edge.
function direct (r) {
  return new Reply(r).send('x')
}

function both (r) {
  direct(r)
  respondWith(r, 'y')
}

module.exports = { Reply, awaitResult, pipePayload, writePayload, notFound, respondWith, direct, both }
