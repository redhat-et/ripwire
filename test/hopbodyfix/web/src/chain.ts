// A four-hop chain: no middle body prints, next= names the first middle hop.
export function stepOne(n: number): number {
  return stepTwo(n + 1)
}
export function stepTwo(n: number): number {
  return stepThree(n * 2)
}
export function stepThree(n: number): number {
  return stepFour(n - 3)
}
export function stepFour(n: number): number {
  return stepFive(n / 4)
}
export function stepFive(n: number): number {
  return n
}
