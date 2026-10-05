import * as h from './helpers'
import * as tok from './utils/token'
export function nsUse(o: Record<string, string>): string { return h.stringify(o) }
export function nsVerify(t: string): boolean { return tok.verify(t) }
