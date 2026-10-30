import type { Provider } from '../driver/iface'
import { Box } from './box'
export class Executor {
  #provider: Provider
  pub: Provider
  late!: Provider
  untyped
  #boxp: Box
  next: Executor | undefined
  self2: Executor
  constructor(provider: Provider) {
    this.#provider = provider
    this.pub = provider
    this.late = provider
    this.untyped = provider
    this.#boxp = new Box()
    this.self2 = this
  }
  provide(x: number): number {
    return this.#provider.provide(x)
  }
  viaPublic(x: number): number {
    return this.pub.provide(x)
  }
  viaLate(x: number): number {
    return this.late.provide(x)
  }
  viaUntyped(x: number): number {
    return this.untyped.provide(x)
  }
  viaPrivBox(x: number): number {
    return this.#boxp.provide(x)
  }
  viaSelfField(x: number): number {
    return this.self2.provide(x)
  }
}
