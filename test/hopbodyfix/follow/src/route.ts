import { runPipeline } from './core'

// a second one-line wrapper: the follow goes on to its callee
export function forwardInput(input: Request): Promise<Response> {
  return runPipeline(input)
}

// the four-line wrapper's callee: reached from nowhere else, so only a (wrong) follow would print it
export function stampInput(input: Request): Promise<Response> {
  return Promise.resolve(new Response(input.url))
}
