import { Context } from '../context'

// Bm: a WHATWG Headers .get on the raw request, beside Context.get in the imported class.
export function bearer(ctx: Context, headerName: string): string | null {
  const credentials = ctx.req.raw.headers.get(headerName)
  return typeof credentials === 'string' ? credentials : null
}

// Near miss: an annotated parameter IS evidence.
export function readUser(c: Context): unknown {
  return c.get('user')
}
