// A tiny request pipeline: Server.fetch is a one-line wrapper, Server.dispatch holds the flow.
import { compose } from './compose'
import { getPath, matchRoute } from './router'

export class Server {
  fetch(request: Request): Promise<Response> {
    return this.dispatch(request)
  }

  dispatch(request: Request): Promise<Response> {
    const path = getPath(request)
    const handlers = matchRoute(path)
    if (handlers.length === 0) {
      return Promise.resolve(new Response('not found', { status: 404 }))
    }
    const composed = compose(handlers)
    return composed(request)
  }

  // two calls: not a thin wrapper, never followed
  listen(request: Request): Promise<Response> {
    auditRequest(request)
    return this.dispatch(request)
  }
}

export function auditRequest(request: Request): void {
  console.log(request.url)
}
