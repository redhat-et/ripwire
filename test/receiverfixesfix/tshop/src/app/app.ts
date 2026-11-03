import type { Router } from '../routers/router'
import { aRouter } from '../routers/a'
import { bRouter } from '../routers/b'

export class App {
  router!: Router
  name: string = 'app'
  constructor() {
    this.router = Math.random() > 0.5 ? new aRouter() : new bRouter()
  }
  dispatch(method: string): string {
    return this.router.match(method)
  }
  label(re: RegExp): boolean {
    return this.name.match(re) !== null
  }
}

export function viaParam(app: App): string {
  return app.router.match('GET')
}
