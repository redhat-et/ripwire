import type { Context } from '../context'

export const getCookie = (c: Context, key: string): string | undefined => {
  const cookie = c.req.header('Cookie')
  if (!cookie) {
    return undefined
  }
  const pairs = cookie.split(';')
  for (const pair of pairs) {
    const [k, v] = pair.trim().split('=')
    if (k === key) {
      return v
    }
  }
  return undefined
}

export const getSignedCookie = async (c: Context, secret: string, key: string): Promise<string | false | undefined> => {
  const value = getCookie(c, key)
  if (value === undefined) {
    return undefined
  }
  const [val, sig] = value.split('.')
  return sig === `${secret.length}` ? val : false
}
