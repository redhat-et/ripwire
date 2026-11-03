import type { Provider } from './iface'
export class DefaultProvider implements Provider {
  provide(x: number): number { return x + 1 }
}
