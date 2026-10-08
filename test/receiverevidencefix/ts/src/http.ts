import { Response as AppResponse } from './response'

// An in-repo method named like Date#getTime.
export class Clock {
  getTime(): number {
    return 0
  }
}

// reply: the global Response (this file never imports one under that name) and Date#getTime.
export function reply(body: string): Response {
  const stamp = new Date().getTime()
  return new Response(body + stamp)
}

// stamped: a local Date's getTime.
export function stamped(): number {
  const d = new Date()
  return d.getTime()
}

// Near misses: a constructed local of the in-repo class, and the in-repo Response through its import alias.
export function local(): number {
  const c = new Clock()
  return c.getTime()
}

export function wrap(body: string): AppResponse {
  return new AppResponse(body)
}
