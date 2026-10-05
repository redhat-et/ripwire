import { parse } from './utils/cookie'
import { App } from './base'

// True edges: a named import of the in-repo parse, and a method call on a constructed App.
export function readCookie(raw: string): Record<string, string> {
  return parse(raw)
}

export function serve(req: Request): Response {
  const app = new App()
  return app.dispatch(req)
}
