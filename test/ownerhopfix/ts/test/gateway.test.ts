// a test-only helper whose name equals a builtin method the gateway calls (TextEncoder#encode)
function encode(s: string): string { return Buffer.from(s).toString('base64') }
export const sample = encode('a.b.c')
