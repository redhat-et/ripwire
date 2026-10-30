import { forwardInput, stampInput } from './route'

// the public entry: a one-line wrapper
export function handleRequest(request: Request): Promise<Response> {
  return forwardInput(request)
}

// one call, but four statement lines: not thin, never followed
export function handleTimedRequest(request: Request): Promise<Response> {
  const started = Date.now()
  const label = request.url
  const tag = label + started
  return stampInput(new Request(tag))
}
