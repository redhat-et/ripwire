'use strict'
// URLSearchParams.append beside an in-repo append method.
function encode (obj) {
  const params = new URLSearchParams()
  for (const k of Object.keys(obj)) params.append(k, obj[k])
  return params.toString()
}
module.exports = { encode }
