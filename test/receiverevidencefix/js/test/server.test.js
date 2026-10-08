'use strict'
// A test double whose `on` no production file can reach.
const fakeServer = {
  on () {},
  listen () {}
}
module.exports = fakeServer
