export class Cache {
  private entries: Record<string, unknown> = {}

  get(key: string): unknown {
    return this.entries[key]
  }

  set(key: string, value: unknown): void {
    this.entries[key] = value
  }
}
