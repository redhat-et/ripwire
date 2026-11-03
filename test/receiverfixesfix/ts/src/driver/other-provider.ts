import type { Provider } from './iface'
export class OtherProvider implements Provider {
  provide(x: number): number { return x + 2 }
}
