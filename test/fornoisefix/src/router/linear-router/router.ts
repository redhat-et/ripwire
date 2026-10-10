import type { ParamIndexMap, Params, Result, Router } from '../../router'
import { METHOD_NAME_ALL, UnsupportedPathError } from '../../router'

type Route<T> = [string, string, T]

export class LinearRouter<T> implements Router<T> {
  name: string = 'LinearRouter'
  #routes: Route<T>[] = []

  add(method: string, path: string, handler: T) {
    for (let i = 0, len = this.#routes.length; i < len; i++) {
      if (this.#routes[i][0] === method && this.#routes[i][1] === path) {
        throw new UnsupportedPathError(`${method} ${path}`)
      }
    }
    this.#routes.push([method, path, handler])
  }

  match(method: string, path: string): Result<T> {
    const handlers: [T, Params][] = []
    ROUTES_LOOP: for (let i = 0, len = this.#routes.length; i < len; i++) {
      const [routeMethod, routePath, handler] = this.#routes[i]
      if (routeMethod === method || routeMethod === METHOD_NAME_ALL) {
        if (routePath === '*' || routePath === '/*') {
          handlers.push([handler, Object.create(null)])
          continue
        }
        if (routePath === path) {
          handlers.push([handler, Object.create(null)])
          continue ROUTES_LOOP
        }
      }
    }
    return [handlers]
  }
}
