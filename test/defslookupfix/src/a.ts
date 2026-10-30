export class A {
  run(): number { return helperA() }
}
export function helperA(): number { return 1 }
export function callsA(a: A): number { return a.run() }
