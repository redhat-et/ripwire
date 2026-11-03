import type { Sink } from './sink'
export class Solo {
  out: Sink
  constructor(s: Sink) { this.out = s }
  write(x: number): number {
    return x
  }
  flush(): number {
    return this.out.write(1)
  }
}
export function write(x: number): number {
  return x + 1
}
