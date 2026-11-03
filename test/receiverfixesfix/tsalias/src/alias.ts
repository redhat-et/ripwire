import type { Provider } from './iface'
type Either = Provider | Exec
export class Exec {
  e: Either
  constructor(p: Either) { this.e = p }
  provide(x: number): number { return x }
  viaUnion(x: number): number {
    return this.e.provide(x)
  }
}
export class Base {
  ping(): number { return 0 }
}
type B = Base
export class D extends Base {
  f: B
  constructor(b: B) { super(); this.f = b }
  ping(): number { return 1 }
  viaBase(): number {
    return this.f.ping()
  }
}
