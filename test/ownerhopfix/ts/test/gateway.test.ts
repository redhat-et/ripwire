// a test-only helper whose name equals a builtin method the gateway calls (TextEncoder#encode); it has a PROVEN callee
// (pad, same file), so a test-filter regression would seat it as an owner ROW, not only count it in noedge=
function pad(s: string): string { return s + '=' }
function encode(s: string): string { return pad(Buffer.from(s).toString('base64')) }
export const sample = encode('a.b.c')
