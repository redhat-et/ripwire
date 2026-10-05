// A cookie parser spelled like JSON.parse.
export const parse = (cookie: string): Record<string, string> => {
  const out: Record<string, string> = {}
  for (const pair of cookie.split(';')) {
    const [k, v] = pair.split('=')
    out[k] = v
  }
  return out
}
