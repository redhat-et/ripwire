// Atomics is a global: its add is never this file's add, nor a router's.
export function add(a: number, b: number): number {
  return a + b
}

export function bump(arr: Int32Array): number {
  return Atomics.add(arr, 0, 1)
}
