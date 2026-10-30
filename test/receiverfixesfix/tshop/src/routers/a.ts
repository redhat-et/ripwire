import type { Router } from './router'
export class aRouter implements Router {
  match(method: string): string {
    return method + 'a'
  }
}
