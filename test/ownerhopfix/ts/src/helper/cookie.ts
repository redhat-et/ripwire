// readCookie: one cookie value out of a raw Cookie header.
export const readCookie = (header: string, name: string): string => {
  for (const part of header.split(';')) {
    const [k, v] = part.trim().split('=')
    if (k === name) return v
  }
  return ''
}
