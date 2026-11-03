import type { Router } from '../routers/router'
import { R1Router, R2Router, R3Router, R4Router, R5Router, R6Router, R7Router, R8Router, R9Router, R10Router, R11Router, R12Router, R13Router, R14Router, R15Router, R16Router } from '../routers/all'

export class App {
  router!: Router
  name: string = 'app'
  constructor() {
    this.router = Math.random() > 0.5 ? new R1Router() : new R2Router()
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
