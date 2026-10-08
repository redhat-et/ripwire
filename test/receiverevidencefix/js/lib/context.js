'use strict'
module.exports = {
  onerror (err) {
    this.app.emit('error', err, this)
  }
}
