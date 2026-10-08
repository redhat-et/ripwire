import type { Router } from './router'

// Bm: `router` walks the inner routers; SmartRouter's own add is never what it calls.
export class SmartRouter<T> implements Router<T> {
  private routers: Router<T>[] = []
  private pending: [string, string, T][] = []

  constructor(init: { routers: Router<T>[] }) {
    this.routers = init.routers
  }

  add(method: string, path: string, handler: T): void {
    this.pending.push([method, path, handler])
  }

  match(method: string, path: string): T[] {
    for (const router of this.routers) {
      for (const p of this.pending) {
        router.add(...p)
      }
      return router.match(method, path)
    }
    return []
  }
}
