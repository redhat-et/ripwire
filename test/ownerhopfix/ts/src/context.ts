// a request context; the untyped `store.remember` in gateway can bind here only by NAME
export class Context {
  store: Record<string, unknown> = {}
  remember(key: string, value: unknown) { this.store[key] = value }
}
