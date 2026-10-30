import type { Router } from './router'
export class bRouter implements Router {
  match(method: string): string {
    return method + 'b'
  }
}
