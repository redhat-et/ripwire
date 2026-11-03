import type { Provider } from '../driver/iface'
export class Peer implements Provider {
  other: Provider
  constructor(o: Provider) { this.other = o }
  provide(x: number): number {
    return this.other.provide(x)
  }
}
