export interface Router<T> {
  add(method: string, path: string, handler: T): void
  match(method: string, path: string): T[]
}
