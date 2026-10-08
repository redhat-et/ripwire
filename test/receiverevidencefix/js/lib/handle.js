'use strict'
// A member call on a route context reaches the user's handler, not this module's own function of that name.
function handler (request, reply) {
  return reply
}

function run (context, request, reply) {
  return context.handler(request, reply)
}

function wrapped (request, reply) {
  return handler(request, reply)
}

module.exports = { handler, run, wrapped }
