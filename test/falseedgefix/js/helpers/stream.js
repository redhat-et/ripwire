'use strict'

// A test double whose method is spelled like the npm package the code requires.
class FakeStream {
  destroy () { this.destroyed = true }
}

module.exports = FakeStream
