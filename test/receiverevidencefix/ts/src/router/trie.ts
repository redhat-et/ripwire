import type { Router } from './router'

export class TrieRouter<T> implements Router<T> {
  private routes: [string, string, T][] = []

  add(method: string, path: string, handler: T): void {
    this.routes.push([method, path, handler])
  }

  match(method: string, path: string): T[] {
    return this.routes.filter((r) => r[0] === method && r[1] === path).map((r) => r[2])
  }
}
