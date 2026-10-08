export class Context {
  private vars = new Map<string, unknown>()
  req: { raw: Request }

  constructor(raw: Request) {
    this.req = { raw }
  }

  get(key: string): unknown {
    return this.vars.get(key)
  }

  set(key: string, value: unknown): void {
    this.vars.set(key, value)
  }
}
