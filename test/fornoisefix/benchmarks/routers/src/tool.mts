import type { Router } from '../../../src/router'

export interface Route {
  method: string
  path: string
}

/** The interface every benchmarked router adapter must implement; existing routers are wrapped by it. */
export interface RouterInterface {
  name: string
  match(route: Route): unknown
}

export const createHonoRouter = (name: string, router: Router<unknown>): RouterInterface => {
  return {
    name,
    match: (route: Route) => router.match(route.method, route.path),
  }
}
