import * as q from '../lib/query.js'
import util from '../lib/util.js'
export function nsUse (o) { return q.stringify(o) }
export function defUse (a, b) { return util.max(a, b) }
