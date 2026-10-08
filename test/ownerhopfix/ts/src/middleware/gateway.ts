import { readCookie } from '../helper/cookie'
import { checkSessionToken } from '../session/check'
// gateway: the middleware in front of every route.
export function gateway(ctx, cookie: string) {
  const raw = readCookie(ctx.header, cookie)
  const payload = checkSessionToken(raw)
  const bytes = new TextEncoder().encode(raw)
  const store: any = ctx
  store.remember('payload', payload)
  return bytes.length
}
