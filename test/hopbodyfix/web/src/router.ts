import type { Handler } from './compose'

const table: Record<string, Handler[]> = {}

export function getPath(request: Request): string {
  return new URL(request.url).pathname
}

export function matchRoute(path: string): Handler[] {
  return table[path] ?? []
}
