export interface HonoRequest {
  url: string
  header(name: string): string | undefined
}

export class Context {
  req: HonoRequest
  #var: Map<string, unknown> = new Map()
  constructor(req: HonoRequest) {
    this.req = req
  }
  set(key: string, value: unknown): void {
    this.#var.set(key, value)
  }
  get(key: string): unknown {
    return this.#var.get(key)
  }
}
