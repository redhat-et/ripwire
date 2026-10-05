'use strict'

// A query-string helper object whose properties are spelled like JSON's and URLSearchParams' methods.
module.exports = {
  parse: (str) => str.split('&'),
  stringify: (obj) => {
    const params = new URLSearchParams()
    for (const k of Object.keys(obj)) params.append(k, obj[k])
    return params.toString()
  }
}
