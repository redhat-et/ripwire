// A two-hop chain whose middle hop no question word names: the graph-verb block prints its body.
export function gatewayEntry(input: string): string {
  const a = input.length
  const b = a + 1
  const c = String(b)
  return relayHop(input + c)
}
export function relayHop(input: string): string {
  const trimmed = input.trim()
  const upper = trimmed.toUpperCase()
  const marked = upper + '!'
  return finalStage(marked)
}
export function finalStage(input: string): string {
  return input
}
// decoys the question's words rank above the middle hop
export function gatewayEntryCount(): number {
  return 1
}
export function finalStageCount(): number {
  return 2
}
export function gatewayFinalStageLabel(): string {
  return 'gateway final stage'
}
